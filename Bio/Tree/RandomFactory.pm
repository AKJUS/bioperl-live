# $Id$
#
# BioPerl module for Bio::Tree::RandomFactory
#
# Cared for by Jason Stajich <jason@bioperl.org>
#
# Copyright Jason Stajich
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::Tree::RandomFactory - TreeFactory for generating Random Trees

=head1 SYNOPSIS

  use Bio::Tree::RandomFactory
  my @taxonnames;
  my $factory = new Bio::Tree::RandomFactory( -samples => \@taxonnames,
  					      -maxcount => 10);

  # or for anonymous samples

  my $factory = new Bio::Tree::RandomFactory( -sample_size => 6,
					      -maxcount => 50);


  my $tree = $factory->next_tree;

=head1 DESCRIPTION

Builds a random tree every time next_tree is called or up to -maxcount times.

This module was originally written for Coalescent simulations see
L<Bio::PopGen::Simulation::Coalescent>.  I've left the next_tree
method intact although it is not generating random trees in the
phylogenetic sense.  I would be happy for someone to provide
alternative implementations which can be used here.  As written it
will generate random topologies but the branch lengths are built from
assumptions in the coalescent and are not appropriate for phylogenetic
analyses.

This algorithm is based on the make_tree algorithm from Richard Hudson 1990.

Hudson, R. R. 1990. Gene genealogies and the coalescent
       process. Pp. 1-44 in D. Futuyma and J.  Antonovics, eds. Oxford
       surveys in evolutionary biology. Vol. 7. Oxford University
       Press, New York


=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org              - General discussion
  http://bioperl.org/MailList.shtml  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via
the web:

  http://bugzilla.bioperl.org/

=head1 AUTHOR - Jason Stajich

Email jason@bioperl.org

=head1 CONTRIBUTORS

Matthew Hahn, E<lt>matthew.hahn@duke.eduE<gt>

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::Tree::RandomFactory;
use vars qw(@ISA $PRECISION_DIGITS);
use strict;

$PRECISION_DIGITS = 3; # Precision for the branchlength

use Bio::Factory::TreeFactoryI;
use Bio::Root::Root;
use Bio::TreeIO::TreeEventBuilder;
use Bio::Tree::AlleleNode;

@ISA = qw(Bio::Root::Root Bio::Factory::TreeFactoryI );

=head2 new

 Title   : new
 Usage   : my $factory = new Bio::Tree::RandomFactory(-samples => \@samples,
						      -maxcount=> $N);
 Function: Initializes a Bio::Tree::RandomFactory object
 Returns : Bio::Tree::RandomFactory
 Args    :


=cut

sub new{
   my ($class,@args) = @_;
   my $self = $class->SUPER::new(@args);
   
   $self->{'_eventbuilder'} = new Bio::TreeIO::TreeEventBuilder();
   $self->{'_treecounter'} = 0;
   $self->{'_maxcount'} = 0;
   my ($maxcount, $samps,$samplesize ) = $self->_rearrange([qw(MAXCOUNT
							       SAMPLES
							       SAMPLE_SIZE)],
							   @args);
   my @samples;
   
   if( ! defined $samps ) { 
       if( ! defined $samplesize || $samplesize <= 0 ) { 
	   $self->throw("Must specify a valid samplesize if parameter -SAMPLE is not specified");
       }
       foreach ( 1..$samplesize ) { push @samples, "Samp$_"; }      
   } else { 
       if( ref($samps) =~ /ARRAY/i ) { 
	   $self->throw("Must specify a valid ARRAY reference to the parameter -SAMPLES, did you forget a leading '\\'?");
       }
       @samples = @$samps;
   }
   
   $self->samples(\@samples);
   $self->sample_size(scalar @samples);
   defined $maxcount && $self->maxcount($maxcount);   
   return $self;
}

=head2 next_tree

 Title   : next_tree
 Usage   : my $tree = $factory->next_tree
 Function: Returns a random tree based on the initialized number of nodes
           NOTE: if maxcount is not specified on initialization or
                 set to a valid integer, subsequent calls to next_tree will 
                 continue to return random trees and never return undef

 Returns : Bio::Tree::TreeI object
 Args    : none

=cut

sub next_tree{
   my ($self) = @_;
   # If maxcount is set to something non-zero then next tree will
   # continue to return valid trees until maxcount is reached
   # otherwise will always return trees 
   return undef if( $self->maxcount &&
		    $self->{'_treecounter'}++ >= $self->maxcount );
   my $size = $self->sample_size;
   
   my $in;
   my @tree = ();
   my @list = ();
   
   for($in=0;$in < 2*$size -1; $in++ ) { 
       push @tree, { 'nodenum' => "Node$in" };
   }
   # in C we would have 2 arrays
   # an array of nodes (tree)
   # and array of pointers to these nodes (list)
   # and we just shuffle the list items to do the 
   # tree topology generation
   # instead in perl, we will have a list of hashes (nodes) called @tree
   # and a list of integers representing the indexes in tree called @list

   for($in=0;$in < $size;$in++)  {
       $tree[$in]->{'time'} = 0;
       $tree[$in]->{'desc1'} = undef;
       $tree[$in]->{'desc2'} = undef;
       push @list, $in;
   }

   my $t=0;
   # generate times for the nodes
   for($in = $size; $in > 1; $in-- ) {
	$t+= -2.0 * log(1 - $self->random(1)) / ( $in * ($in-1) );    
	$tree[2 * $size - $in]->{'time'} =$t;
    }
   # topology generation
   for ($in = $size; $in > 1; $in-- ) {
       my $pick = int $self->random($in);    
       my $nodeindex = $list[$pick];       
       my $swap = 2 * $size - $in;       
       $tree[$swap]->{'desc1'} = $nodeindex;	
       $list[$pick] = $list[$in-1];       
       $pick = int rand($in - 1);    
       $nodeindex = $list[$pick];
       $tree[$swap]->{'desc2'} = $nodeindex;	
       $list[$pick] = $swap;
   }
   # Let's convert the hashes into nodes

   my @nodes = ();   
   foreach my $n ( @tree ) { 
       push @nodes, 
	   new Bio::Tree::AlleleNode(-id => $n->{'nodenum'},
				     -branch_length => $n->{'time'});
   }
   my $ct = 0;
   foreach my $node ( @nodes ) { 
       my $n = $tree[$ct++];
       if( defined $n->{'desc1'} ) {
	   $node->add_Descendent($nodes[$n->{'desc1'}]);
       }
       if( defined $n->{'desc2'} ) { 
	   $node->add_Descendent($nodes[$n->{'desc2'}]);
       }
   }   
   my $T = new Bio::Tree::Tree(-root => pop @nodes );
   return $T;
}


=head2 maxcount

 Title   : maxcount
 Usage   : $obj->maxcount($newval)
 Function: 
 Returns : Maxcount value
 Args    : newvalue (optional)


=cut

sub maxcount{
   my ($self,$value) = @_;
   if( defined $value) {
       if( $value =~ /^(\d+)/ ) { 
	   $self->{'maxcount'} = $1;
       } else { 
	   $self->warn("Must specify a valid Positive integer to maxcount");
	   $self->{'maxcount'} = 0;
       }
  }
   return $self->{'_maxcount'};
}

=head2 samples

 Title   : samples
 Usage   : $obj->samples($newval)
 Function: 
 Example : 
 Returns : value of samples
 Args    : newvalue (optional)


=cut

sub samples{
   my ($self,$value) = @_;
   if( defined $value) {
       if( ref($value) !~ /ARRAY/i ) { 
	   $self->warn("Must specify a valid array ref to the method 'samples'");
	   $value = [];
       } 
      $self->{'samples'} = $value;
    }
    return $self->{'samples'};

}

=head2 sample_size

 Title   : sample_size
 Usage   : $obj->sample_size($newval)
 Function: 
 Example : 
 Returns : value of sample_size
 Args    : newvalue (optional)


=cut

sub sample_size{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'sample_size'} = $value;
    }
    return $self->{'sample_size'};

}

=head2 attach_EventHandler

 Title   : attach_EventHandler
 Usage   : $parser->attatch_EventHandler($handler)
 Function: Adds an event handler to listen for events
 Returns : none
 Args    : Bio::Event::EventHandlerI

=cut

sub attach_EventHandler{
    my ($self,$handler) = @_;
    return if( ! $handler );
    if( ! $handler->isa('Bio::Event::EventHandlerI') ) {
	$self->warn("Ignoring request to attatch handler ".ref($handler). ' because it is not a Bio::Event::EventHandlerI');
    }
    $self->{'_handler'} = $handler;
    return;
}

=head2 _eventHandler

 Title   : _eventHandler
 Usage   : private
 Function: Get the EventHandler
 Returns : Bio::Event::EventHandlerI
 Args    : none


=cut

sub _eventHandler{
   my ($self) = @_;
   return $self->{'_handler'};
}

=head2 random

 Title   : random
 Usage   : my $rfloat = $node->random($size)
 Function: Generates a random number between 0 and $size
           This is abstracted so that someone can override and provide their
           own special RNG.  This is expected to be a uniform RNG.
 Returns : Floating point random
 Args    : $maximum size for random number (defaults to 1)


=cut

sub random{
   my ($self,$max) = @_;
   return rand($max);
}

1;
