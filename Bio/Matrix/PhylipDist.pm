# BioPerl module for Bio::Matrix::PhylipDist
#
# Cared for by Shawn Hoon <shawnh@fugu-sg.org>
#
# Copyright Shawn Hoon
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::Matrix::PhylipDist - A Phylip Distance Matrix object 

=head1 SYNOPSIS

  use Bio::Tools::Phylo::Phylip::ProtDist;
  my $dist = Bio::Tools::Phylo::Phylip::ProtDist->new(
    -file=>"protdist.out",
    -program=>"ProtDist");
  #or
   my $dist = Bio::Tools::Phylo::Phylip::ProtDist->new(
    -fh=>"protdist.out",
    -program=>"ProtDist");


  #get specific entries
  my $distance_value = $dist->get_entry('ALPHA','BETA');
  my @columns        = $dist->get_column('ALPHA');
  my @rows           = $dist->get_row('BETA');
  my @diagonal       = $dist->get_diagonal();

  #print the matrix in phylip numerical format
  print $dist->print_matrix;

=head1 DESCRIPTION

Simple object for holding Distance Matrices generated by the following Phylip programs:

1) dnadist
2) protdist
3) restdist

It currently handles parsing of the matrix without the data output option.

    5
Alpha          0.00000  4.23419  3.63330  6.20865  3.45431
Beta           4.23419  0.00000  3.49289  3.36540  4.29179
Gamma          3.63330  3.49289  0.00000  3.68733  5.84929
Delta          6.20865  3.36540  3.68733  0.00000  4.43345
Epsilon        3.45431  4.29179  5.84929  4.43345  0.00000

=head1 FEEDBACK


=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to one
of the Bioperl mailing lists. Your participation is much appreciated.

  bioperl-l@bioperl.org              - General discussion
  http://bio.perl.org/MailList.html  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
the bugs and their resolution.  Bug reports can be submitted via email
or the web:

  bioperl-bugs@bioperl.org
  http://bugzilla.bioperl.org/

=head1 AUTHOR - Shawn Hoon

Email shawnh@fugu-sg.org


=head1 APPENDIX


The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a "_".

=cut

# Let the code begin...

package Bio::Matrix::PhylipDist;
use strict;

use vars qw(@ISA);

use Bio::Root::Root;
use Bio::Tools::Phylo::Phylip::ProtDist;

@ISA = qw(Bio::Root::Root);

=head2 new

 Title   : new
 Usage   : my $family = Bio::Matrix::PhylipDist->new(-file=>"protdist.out",
                                                     -program=>"protdist");
 Function: Constructor for PhylipDist Object
 Returns : L<Bio::Matrix::PhylipDist>

=cut

sub new {
    my ($class,@args) = @_;
    my $self = $class->SUPER::new(@args);
    my ($matrix,$values, $names,
	$program) = $self->_rearrange([qw(MATRIX VALUES 
					  NAMES PROGRAM)],@args);
    
    ($matrix && $values && $names) || 
	$self->throw("Need a file or file handle!");

    $program && $self->program($program);
    
    $self->_matrix($matrix) if $matrix;
    $self->_values($values) if $values;
    $self->names($names) if $names;

    return $self;
}

=head2 get_entry

 Title   : get_entry
 Usage   : $matrix->get_entry();
 Function: returns a particular entry 
 Returns : a float
 Arguments:  string id1, string id2

=cut

sub get_entry {
  my ($self,$row,$column) = @_;
  $row && $column || $self->throw("Need at least 2 ids");
  my %matrix = %{$self->_matrix};
  my @values = @{$self->_values};
  if(ref $matrix{$row}{$column}){
      my ($i,$j) = @{$matrix{$row}{$column}};
      return $values[$i][$j];
  }
  return;

}

=head2 get_row

 Title   : get_row
 Usage   : $matrix->get_row('ALPHA');
 Function: returns a particular row 
 Returns : an array of float
 Arguments:  string id1

=cut

sub get_row {
    my ($self,$row) = @_;
    $row || $self->throw("Need at least a row id");

    my %matrix = %{$self->_matrix};
    my @values = @{$self->_values};
    my @names = @{$self->names};
    %matrix->{$row} || return;
    my @row = %{%matrix->{$row}};
    my $row_pointer = $row[1]->[0];
    my $index = scalar(@names)-1;
    return @{$values[$row_pointer]}[0..$index];
}

=head2 get_column

 Title   : get_column
 Usage   : $matrix->get_column('ALPHA');
 Function: returns a particular column 
 Returns : an array of floats 
 Arguments:  string id1

=cut

sub get_column {
    my ($self,$column) = @_;
    $column || $self->throw("Need at least a column id");

    my %matrix = %{$self->_matrix};
    my @values = @{$self->_values};
    my @names = @{$self->names}; 
    %matrix->{$column} || return;
    my @column = %{%matrix->{$column}};
    my $row_pointer = $column[1]->[0];
    my @return;
    for(my $i=0; $i < scalar(@names); $i++){
      push @return, $values[$i][$row_pointer];
    }
    return @return;
} 

=head2 get_diagonal

 Title   : get_diagonal
 Usage   : $matrix->get_diagonal();
 Function: returns the diagonal of the matrix
 Returns : an array of float
 Arguments:  string id1

=cut

sub get_diagonal {
  my ($self) = @_;
  my %matrix = %{$self->_matrix};
  my @values = @{$self->_values};
  my @return;
  foreach my $name (@{$self->names}){
    my ($i,$j) = @{$matrix{$name}{$name}};
    push @return,$values[$i][$j];
  }
  return @return;
}
    
=head2 print_matrix

 Title   : print_matrix
 Usage   : $matrix->print_matrix();
 Function: returns a string of the matrix in phylip format 
 Returns : a string
 Arguments:  

=cut

sub print_matrix {
  my ($self) = @_;
  my @names = @{$self->names};
  my @values = @{$self->_values};
  my %matrix = %{$self->_matrix};
  my $str;
  $str.= (" "x 4). scalar(@names)."\n";
  foreach my $name (@names){
    my $newname = $name. (" " x (15-length($name)));
    $str.=$newname;
    my $count = 0;
    foreach my $n (@names){
      my ($i,$j) = @{$matrix{$name}{$n}};
      if($count < $#names){
        $str.= @values->[$i][$j]. "  ";
      }
      else {
        $str.= @values->[$i][$j];
      }
      $count++;
    }
    $str.="\n";
  }
  return $str;
}

=head2 _matrix

 Title   : _matrix
 Usage   : $matrix->_matrix();
 Function: get/set for hash reference of the pointers
           to the value matrix 
 Returns : hash reference 
 Arguments: hash reference

=cut

sub _matrix {
  my ($self,$val) = @_;
  if($val){
    $self->{'_matrix'} = $val;
  }
  return $self->{'_matrix'};
}


=head2 names

 Title   : names
 Usage   : $matrix->names();
 Function: get/set for array ref of names of sequences
 Returns : an array reference 
 Arguments: an array reference

=cut

sub names {
  my ($self,$val) = @_;
  if($val){
    $self->{"_names"} = $val;
  }
  return $self->{'_names'};
}

=head2 program

 Title   : program
 Usage   : $matrix->program();
 Function: get/set for the program name generating this 
           matrix
 Returns : string
 Arguments: string

=cut

sub program {
  my ($self,$val) = @_;
  if($val){
    $self->{'_program'} = $val;
  }
  return $self->{'_program'};
}

=head2 _values

 Title   : _values
 Usage   : $matrix->_values();
 Function: get/set for array ref of the matrix containing
           distance values 
 Returns : an array reference 
 Arguments: an array reference

=cut

sub _values {
  my ($self,$val) = @_;
  if($val){
    $self->{'_values'} = $val;
  }
  return $self->{'_values'};
}
  
1;


    
    
    


