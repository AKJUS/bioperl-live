# BioPerl modul
#
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

# The original version of the module can be found here:
# http://www.lifecde.com/products/agave/agave.pm
# Modified by Simon Chan
#
#

=head1 NAME

Bio::SeqIO::agave - AGAVE sequence output stream

=head1 SYNOPSIS

It is probably best not to use this object directly, but
rather go through the AnnSeqIO handler system. Go:

    $in  = Bio::SeqIO->new('-file' => "$file_in",
                         '-format' => 'EMBL');

     $out = Bio::SeqIO->new('-file' => ">$file_out",
                         '-format' => 'AGAVE');
  while ( my $seq = $in->next_seq() ) {$out->write_seq($seq); }

=head1 DESCRIPTION

This object can transform Bio::Seq objects to agave xml file.

=cut

# Let the code begin...

package Bio::SeqIO::agave;
use vars qw(@ISA);
use strict;
# Object preamble - inherits from Bio::Root::Object

use IO::File;

use lib '/home/skchan/gq/BIO_SUPPORT/bioperl-live';
use Bio::SeqIO;
use Bio::SeqFeature::Generic;
use Bio::Seq;
use Bio::PrimarySeq;
use Bio::Seq::SeqFactory;
use Bio::Annotation::Reference;
use Bio::Species;

use lib '/home/skchan/gq/BIO_SUPPORT/XML-Writer/XML-Writer-0.510/blib/lib';
use XML::Writer;

use Bio::Seq;

use Data::Dumper;

@ISA = qw(Bio::SeqIO);


sub _initialize {        

  my($self,@args) = @_;
  $self->SUPER::_initialize(@args); # run the constructor of the parent class.
  
  my %tmp = @args ; 
  $self->{'file'} = $tmp{'-file'};

  # filehandle is stored by superclass _initialize

  # print "file: $tmp{-file}\n"; exit;
  if ($self->{'file'} !~ /^>/){
	$self->_process; # parse the thing, but only if it is the input file (ie not outputing agave file).
 	 $self->{'parsed'} = 1;
  }
  $self->{'seqs_stored'} = 0;

}

sub _process {

	my ($self) = @_;
	while (1){

		my $line = $self->_readline;
		### print "line: $line\n";
		next unless $line;
		next if $line =~ /^\s*$/;
		if ($line =~ /<\?xml version/o){
			# do nothing
			# print "line: $line\n";
		} elsif ($line =~ /\<!DOCTYPE (\w+) SYSTEM "([\w\.]+)"\>/){

			# print "1: $1 , 2: $2\n";
			die "This xml file is not in AGAVE format!"
			if $1 ne 'sciobj' || $2 ne 'sciobj.dtd';

		} elsif ($line =~ /<sciobj (.*)>/){

			$self->{'sciobj'} = $self->_process_sciobj($1);
			### print Data::Dumper->Dump([$self]); 
		} elsif ($line =~ /<\/sciobj>/){

			# $self->_store_seqs;
			last;

		} else {
			# print "last line: $line\n"; exit;
		}	

	}

}

sub _process_sciobj {

	my ($self, $attribute_line) = @_;
	my $sciobj;
	$self->_helper_store_attribute_list($attribute_line, \$sciobj);

	my $line = $self->_readline;

	# Zero or more <contig>
	while ($line =~ /<contig\s?(.*?)\s?>/){
		my $contig = $self->_process_contig(\$line, $1);
		push @{$sciobj->{'contig'}}, $contig;
	}

	return $sciobj;
}

sub _process_contig {

	my ($self, $line, $attribute_line) = @_;

	my $contig;
	$$line = $self->_readline;

	# One <db_id>:
	# print "line: $$line\n"; exit;
	$self->_one_tag($line, \$contig, 'db_id');

	# Zero or more <fragment_order>
	$self->_process_fragment_order($line, \$contig);



	return $contig;

}

sub _process_fragment_order {


	my ($self, $line, $data_structure) = @_;

	while ($$line =~ /<fragment_order\s?(.*?)\s?>/){

		my $fragment_order;
		$self->_helper_store_attribute_list($1, \$fragment_order);
		$$line = $self->_readline;

		# One or more <fragment_orientation>
		$self->_process_fragment_orientation($line, \$fragment_order);

		push @{$$data_structure->{'fragment_order'}}, $fragment_order;

	}

	# print "line: $$line\n"; exit;



}

sub _process_fragment_orientation {


	my ($self, $line, $data_structure) = @_;

	my $count = 0;

	# One or more <fragment_orientation>
	while ($$line =~ /<fragment_orientation\s?(.*?)\s?>/){
		
			
		my $fragment_orientation;
		$self->_helper_store_attribute_list($1, \$fragment_orientation);		
		$$line = $self->_readline;

		# One <bio_sequence>
		$$line =~ /<bio_sequence\s?(.*?)\s?>/;
		# print "about to process\n"; exit;
		my $bio_sequence = $self->_process_bio_sequence($line, $1);
		$fragment_orientation->{'bio_sequence'} = $bio_sequence;
		
		push @{$$data_structure->{'fragment_orientation'}}, $fragment_orientation;

		++$count;
	}


	die "Error.  Missing <fragment_orientation> tag.  Got this: $$line" if $count == 0;

}



sub _process_bio_sequence {

	my ($self, $line, $attribute_line) = @_;
	
	my $bio_sequence;

	$self->_helper_store_attribute_list($attribute_line, \$bio_sequence);
	$$line = $self->_readline;
	
	# One <db_id>.  
	$self->_one_tag($line, \$bio_sequence, 'db_id');
	# $line = $self->_readline;	

	# Zero or one <note>.
	$self->_question_mark_tag($line, \$bio_sequence, 'note');
	# $line = $self->_readline;

	# Zero or more <description>
	$self->_question_mark_tag($line, \$bio_sequence, 'description');
	# $line = $self->_readline;

	# Zero or more <keyword>
	$self->_star_tag($line, \$bio_sequence, 'keyword');

	# Zero or one <sequence>
	$self->_question_mark_tag($line, \$bio_sequence, 'sequence');
	# $line = $self->_readline;

	# Zero or one <alt_ids>
	if ($line =~ /<alt_ids>/){ # NOT DONE YET!
		my $alt_ids;
		$bio_sequence->{'alt_ids'} = $self->_process_alt_ids(\$alt_ids);
	}
	

	# Zero or one <xrefs>
	my $xrefs = $self->_process_xrefs($line, \$bio_sequence);
	$bio_sequence->{'xrefs'} = $xrefs || 'null';	

	# $line = $self->_readline;

	# Zero or more <sequence_map>
	# print "line after return: $$line\n"; # <sequence_map label="EMBL/GenBank/SwissProt">
	if ($$line =~ /<sequence_map\s?(.*?)\s?>/){
		my $sequence_map = $self->_process_sequence_map($line);
		push @{$bio_sequence->{'sequence_map'}}, $sequence_map;
	}

	return $bio_sequence;
}

sub _process_xrefs {

	my ($self, $line, $data_structure) = @_;

	my $xrefs;

	# print "line in _process_xrefs: $$line\n"; exit;
	# Zero or one <xrefs>
	if ($$line =~ /<xrefs\s?(.*?)\s?>/){


		# JUST a quick and dirty 'fix' for the moment...
		return if $$line =~ /<xrefs><\/xrefs>/;	

		$$line = $self->_readline;
		# print "line in _process_xrefs: $$line\n";

		# One or more <db_id> or <xref>
		print "before: $$line\n"; exit;
		if ($$line =~ /<db_id|xref\s?(.*?)\s?>/){
			while ($$line =~ /<(db_id|xref)\s?(.*?)\s?>/){
				# print "line: $$line\n";
				if ($1 eq "db_id"){
					my $db_id;
					$self->_one_tag($line, \$db_id, 'db_id');
					push @{$xrefs->{'db_id'}}, $db_id;
				} elsif ($1 eq "xref"){
					my $xref;
					$self->_process_xref($line, \$xref);
				}
			}	

			# print Data::Dumper->Dump([$xrefs]); exit;

			if ($$line =~ /<\/xrefs>/){
				$$line = $self->_readline; # get the next line to be _processed by the next sub.
				return $xrefs;
			}


		} else {
			die "Error.  Missing <db_id> or <xref> tag.  Got this: $$line";
		}

	} else {
		die "nope";
	}


}

sub _process_xref {

	my ($self, $line, $data_structure) = @_;

	# One <db_id>
	


	# Zero or more <xref_property>




}


sub _process_sequence_map {

	my ($self, $line) = @_;

	my $sequence_map;

	# Zero or more <sequence_map>
	while ($$line =~ /<sequence_map\s?(.*?)\s?>/){

		if (defined $1){
			$self->_helper_store_attribute_list($1, \$sequence_map);
		}	        	
		# print Data::Dumper->Dump([$sequence_map]); exit;
		$$line = $self->_readline;

		# Zero or one <note>
		$self->_question_mark_tag($line, \$sequence_map, 'note');		

		if ($$line =~ /<computations\?(.*?)\s?>/){
			# $self->_process_computations();
		}
		
		# Zero or one <annotations>
		if ($$line =~ /<annotations\s?(.*?)\s?>/){
			my $annotations = $self->_process_annotations($line);
			$sequence_map->{'annotations'} = $annotations;
		}


	}

	if ($$line =~ /<\/sequence_map>/){
		return $sequence_map;
	} else {
		die "Error.  Missing </sequence_map>.  Got: $$line";
	}
}

sub _process_annotations {

	my ($self, $line) = @_;
	# ( seq_feature | gene | comp_result )+

	my $annotations;

	$$line = $self->_readline;

	my $count = 0;

	# One or more of these:
	while ($$line =~ /<(seq_feature|gene|comp_result)\s?(.*?)\s?>/){

		if ($$line =~ /<seq_feature\s?(.*?)\s?>/){
			my $seq_feature = $self->_process_seq_feature($line, $1);
			push @{$annotations->{'seq_feature'}}, $seq_feature;
		} elsif ($$line =~ /<gene\s?(.*?)\s?>/){

		} elsif ($$line =~ /<comp_result\s?(.*?)\s?>/){

		}

		++$count;

	}


	die "Error.  Missing <seq_feature> or <gene> or <comp_result> tag.  Got: $$line" if $count == 0;

	#	print Data::Dumper->Dump([$annotations]);

	if ($$line =~ /<\/annotations/){
		$$line = $self->_readline; # get the next line to be _processed by the next sub.
		return $annotations;
	} else {
		die "Error.  Missing </annotations>.  Got: $$line\n";
	}

}

sub _process_seq_feature {

	my ($self, $line, $attribute_line) = @_;

        my $seq_feature;
        $self->_helper_store_attribute_list($attribute_line, \$seq_feature);
        $$line = $self->_readline;

	# Zero or more <classification>
	$self->_process_classification($line, \$seq_feature);

	# Zero or one <note>
	$self->_question_mark_tag($line, \$seq_feature, 'note');

	# One <seq_location>
	$self->_one_tag($line, \$seq_feature, 'seq_location');

	# Zero or one <xrefs>
	$self->_question_mark_tag($line, \$seq_feature, 'xrefs');

	# Zero or one <evidence>
	$self->_process_evidence($line, \$seq_feature);

	# Zero or more <qualifier>
 	# print "_process_qualifier: $$line\n";
	$self->_process_qualifier($line, \$seq_feature);

	# Zero or more <seq_feature>.  A <seq_feature> tag within a <seq_feature> tag?  Oh, well.  Whatever...
	while ($$line =~ /<seq_feature\s?(.*?)\s?>/){
		$self->_process_seq_feature($line, $1);
		$$line = $self->_readline;
	}

	# Zero or more <related_annot>
	while ($$line =~ /<related_annot\s?(.*?)\s?>/){
		$self->_process_related_annot($line, $1);
		$$line = $self->_readline;
	}

	if ($$line =~ /<\/seq_feature>/){
		$$line = $self->_readline; # for the next sub...
		return $seq_feature;
	} else {
		die "Error.  Missing </seq_feature> tag.  Got this: $$line\n";
	}

	# print Data::Dumper->Dump([$seq_feature]); exit;
}

sub _process_qualifier {

	my ($self, $line, $data_structure) = @_;

	# my $qualifier = $$data_structure->{'qualifier'};

	while ($$line =~ /<qualifier\s?(.*?)\s?>(.*?)<\/qualifier>/){

		my $qualifier;
		$self->_helper_store_attribute_list($1, \$qualifier);
		$self->_question_mark_tag($line, \$qualifier, 'qualifier');
		push @{$$data_structure->{'qualifier'}},$qualifier; 		
		
	}


}


sub _process_classification {

	my ($self, $line, $data_structure) = @_;

	my $classification = $$data_structure->{'classification'};

        while ($$line =~ /<classification\s?(.*?)\s?>/){
                                       
		$self->_helper_store_attribute_list($1, \$classification);
                                                                                                      
                # Zero or one <description>
                $self->_question_mark_tag($line, \$classification, 'description');
                                                                                                                                             
                # Zero or more <id_alias>
                $self->_star_tag($line, \$classification, 'id_alias');
                                                                                                                                             
                # Zero or one <evidence>
                $self->_process_evidence($line, \$classification);
                                                                                                                                             
        }


}
sub _process_evidence { # NOT done.

	my ($self, $line, $data_structure) = @_;

	if ($$line =~ /<evidence>/){

		$$line = $self->_readline;

		# One or more <element_id> OR One or more <comp_result>
		while ($$line =~ /<(element_id|comp_result)\s?(.*?)\s?>/){
			if ($$line =~ /<element_id\s?(.*?)\s?>/){
				my $element_id;
				$self->_plus_tag($line, \$element_id, 'element_id');
				push @{$$data_structure->{'element_id'}}, $element_id;
			} elsif ($$line =~ /<comp_result\s?(.*?)\s?>/){
				my $comp_result;
				$self->_process_comp_result($line, \$comp_result, $1);
				push @{$$data_structure->{'comp_result'}}, $comp_result;
			}
			$$line = $self->_readline;
		}

	}


}

sub _process_comp_result { # NOT done.


	my ($self, $line, $comp_result, $attribute_line) = @_;

	$self->_helper_store_attribute_list($attribute_line, $comp_result);
	$$line = $self->_readline;
	
	# Zero or one <note>
	$self->_question_mark_tag($line, $comp_result, 'note');

	# Zero or one <match_desc>
	$self->_question_mark_tag($line, $comp_result, 'match_desc');

	# Zero or one <match_align>
	$self->_question_mark_tag($line, $comp_result, 'match_align');

	# Zero or one <query_region>
	$self->_process_query_region($line, $comp_result);

	# Zero or one <match_region>
	$self->_process_match_region($line, $comp_result);	

	# Zero or more <result_property>
	$self->_star_tag($line, $comp_result, 'result_property');

	# Zero or more <result_group>
	$self->_process_result_group($line, $comp_result);

	# Zero or more <related_annot>
	$self->_process_related_annot($line, $comp_result);
	
}

sub _process_related_annot {

	my ($self, $line, $data_structure) = @_;

	while ($$line =~ /<related_annot\s?(.*?)\s?>/){
		
		my $related_annot;
		# Zero or one <related_annot>
		$self->_helper_store_attribute_list($1, \$related_annot);
		$$line = $self->_readline;

		# One or more <element_id>
		my $element_id_count = 0;
		while ($$line =~ /<element_id\s?(.*?)\s?>/){
			my $element_id;
			$self->_helper_store_attribute_list($1, \$element_id);
			push @{$related_annot->{'element_id'}}, $element_id;
			$$line = $self->_readline;
			++$element_id_count;
		}

		if ($element_id_count == 0){
			die "Error.  Missing <element_id> tag.  Got: $$line";
		}
		
		# Zero or more <sci_property>
		$self->_star_tag($line, \$related_annot, 'sci_property');
		# while ($$line =~ /<sci_property\s?(.*?)\s?>/){
		#
		# }

		push @{$data_structure->{'related_annot'}}, $related_annot;

		unless ($$line =~ /<\/related_annot>/){
			die "Error.  Missing </related_tag>. Got: $$line\n";	
		}

	}


}


sub _process_result_group {

	my ($self, $line, $data_structure) = @_;

	while ($$line =~ /<result_group\s?(.*?)\s?>/){
        	my $result_group = $$data_structure->{'result_group'};
		$self->_helper_store_attribute_list($1, \$result_group);
		
		my $count = 0;
		$$line = $self->_readline;
		while ($$line =~ /<comp_result\s?(.*?)\s?>/){
			# one or more <comp_result>
			$self->_process_comp_result(\$line, \$result_group, $1);
			$$line = $self->_readline;
			++$count;
		}

		die "Error.  No <comp_result></comp_result> tag! Got this: $$line" if $count == 0;
	
		# in the last iteration in the inner while loop, $line will have a value of the closing tag of 'result_group'
		if ($line =~ /<\/result_group>/){
			$$line = $self->_readline;
		} else {
			die "Error.  No </result_tag>!  Got this: $$line";
		}


	}


}

sub _process_match_region {

	my ($self, $line, $data_structure) = @_;

	my $match_region = $data_structure->{'match_region'};

	if ($$line =~ /<match_region\s?(.*?)\s?>(.*?)>/){

		$self->_helper_store_attribute_line($1, \$match_region);
		$$line = $self->_readline;

		# Zero or one db_id | element_id | bio_sequence
		if ($$line =~ /<db_id\s?(.*?)\s?>(.*?)<\/db_id>/){
			$self->_question_mark_tag($line, \$match_region, 'db_id');
		} elsif ($$line =~ /<element_id\s?(.*?)\s?>/){ # empty...
			$self->_question_mark_tag($line, \$match_region, 'element_id');
		} elsif ($$line =~ /<bio_sequence\s?(.*?)\s?>/){
			$match_region->{'bio_sequence'} = $self->_process_bio_sequence($line, $1);
		}

		$$line = $self->_readline;
		if ($$line =~ /<\/match_region>/o){
			$$line = $self->_readline; # get the next line to be _processed by the next sub
			return;
		} else {
			die "No closing tag </match_region>!  Got this: $$line\n";
		}
	
	}
}

sub _process_query_region {

	my ($self, $line, $data_structure) = @_;

	my $query_region = $data_structure->{'query_region'};
	if ($$line =~ /<query_region\s?(.*?)\s?>/){
		$self->_helper_store_attribute_list($1, \$query_region);
		$$line = $self->_readline;
		
		# Zero or one <db_id>
		$self->_question_mark_tag($line, \$query_region, 'db_id');

		if ($$line =~ /<\/query_region>/){
			$$line = $self->_readline; # get the next line to _process.
			return;
		} else {
			die "No closing tag </query_region>.  Got this: $$line\n";
		}
		
	}


}

sub _process_alt_ids {

	my ($self, $data_structure) = @_;
	
	my $line = $self->_readline;
	
	# One or more <db_id>
	$self->_plus_tag(\$line, $data_structure, 'alt_ids');	

}


sub _tag_processing_helper {

	my ($self, $attribute_list, $data_structure, $tag_name, $tag_value, $caller) = @_;
	# print "attribute_list: $attribute_list\n"; 
        if (defined $attribute_list){
                $self->_helper_store_attribute_list($attribute_list, $data_structure);
        }
	# print "tag_name: $tag_name\n";
	if ($caller eq 'star' || $caller eq 'plus'){
		push @{$$data_structure->{$tag_name}}, $tag_value;
	} else {
        	$$data_structure->{$tag_name} = $tag_value || 'null';
	}

}

sub _one_tag {

	my ($self, $line, $data_structure, $tag_name) = @_;
	
	die "Error.  Missing <$tag_name></$tag_name>.  Got this instead: $$line" if $$line !~ /\<$tag_name/;
	# print "line: $$line\n"; exit;
	# die "$$line\n" if $tag_name eq "seq_location";
	# <db_id id="J00231" version="9" db_code="EMBL" />
	if ($$line =~ /<$tag_name\s?(.*?)\s?\/?>((.*?)<\/$tag_name>)?/){
		$self->_tag_processing_helper($1, $data_structure, $tag_name, $2, 'one');
		$$line = $self->_readline;
	} else {
		die "Error.  Do not understand this line: $$line";
	}
}

sub _question_mark_tag {

	my ($self, $line, $data_structure, $tag_name) = @_;
	# $line =~ /<$tag_name (.*)\s?>(\w+)<\/$tag_nam
	if ($$line =~ /<$tag_name\s?(.*?)\s?>(.*?)<\/$tag_name>/){
		$self->_tag_processing_helper($1, $data_structure, $tag_name, $2, 'question mark');
		$$line = $self->_readline;
	}

}


sub _star_tag {

	my ($self, $line, $data_structure, $tag_name) = @_;

	# print "_star_tag: $$line\n";
	while ($$line =~ /<$tag_name\s?(.*?)\s?>(.*?)<\/$tag_name>/){
		# print "iss: $$line\n";
		$self->_tag_processing_helper($1, $data_structure, $tag_name, $2, 'star');
		$$line = $self->_readline;
	}

}

sub _plus_tag {

	my ($self, $line, $data_structure, $tag_name) = @_;
	
	if ($$line =~ /<$tag_name\s?(.*?)\s?>(.*?)<\/$tag_name>/){

		



	} else {
		die "Error.  Missing <$tag_name></$tag_name>.  Got: $$line";		
	}

}


sub _helper_store_attribute_list {

        my ($self, $attribute_line, $data_structure) = @_;

	# print "attribute_line: $attribute_line\n";
        my %attribs = ($attribute_line =~ /(\w+)\s*=\s*"([^"]*)"/g);
                                                                                                                                             
        my $attribute_list;
        for my $key (keys %attribs){
                # print "key: $key , value: $attribs{$key}\n";
                $$data_structure->{$key} = $attribs{$key};
        }
}



sub _store_seqs {

	my ($self) = @_;

	# print Data::Dumper->Dump([$self]);	exit;
	# get all the biosequences...
	# my $bio_sequence_objects = $self->{'sciobj'}->{'contig'};

	my $sciobj = $self->{'sciobj'};

	for my $contig (@{$sciobj->{'contig'}}){


		for my $fragment_order (@{$contig->{'fragment_order'}}){
			
			for my $fragment_orientation (@{$fragment_order->{'fragment_orientation'}}){

				# for my $bio_sequence (@{$fragment_orientation->{'bio_sequence'}}){

					my $bio_sequence = $fragment_orientation->{'bio_sequence'};

			                my $sequence = $bio_sequence->{sequence};
	        		        my $accession_number = $bio_sequence->{sequence_id}; # also use for primary_id
			                my $organism = $bio_sequence->{organism};
			                my $description = $bio_sequence->{description};
	                                                                                                                                             
	        		        my $primary_seq = Bio::PrimarySeq->new(
                                                                -id => $accession_number,
                                                                -alphabet => 'dna',
                                                                -seq => $sequence,
                                                                -desc => $description,
                                                        );

                                        my $seq = Bio::Seq->new (
                                                -display_id => $accession_number,
                                                -accession_number => $accession_number,
                                                -primary_seq => $primary_seq,
                                                -seq => $sequence,
                                                -description => $description,
                                        );
                                                                                                                                             
                                        my $organism_name = $bio_sequence->{organism_name};
					if (defined $organism_name){
						my ($genus_name, $species_name) = split(' ', $organism_name);
	                                        my $species = Bio::Species->new();
						$species->classification(qw($species_name $genus_name));
                                        	$seq->species($organism_name);
					}                                                                    
                                                                         
                                        my $keywords = $bio_sequence->{keyword};
                                        my %key_to_value;
                                                                                                                                             
                                        for my $keywords (@$keywords){
                                                my @words = split(':', $keywords);
                                                for (my $i = 0; $i < scalar @words - 1; $i++){
                                                        if ($i % 2 == 0){
                                                                my $j = $i; $j++;
                                                                # print "$words[$i] , $words[$j]\n";
                                                                $key_to_value{$words[$i]} = $words[$j];
                                                        }
                                                }
                                                my $reference = Bio::Annotation::Reference->new(-authors => $key_to_value{authors},
                                                                        -title => $key_to_value{title},
                                                                        -database => $key_to_value{database},
                                                                        -pubmed => $key_to_value{pubmed},
                                                                        );
                                                $seq->annotation->add_Annotation('reference', $reference);
                                                                                                                                             
                                        } # close for my $keywords


					#  print Data::Dumper->Dump([$bio_sequence]); print "here\n"; exit;
					if (defined $bio_sequence->{'sequence_map'}){

						for my $sequence_map (@{$bio_sequence->{'sequence_map'}}){

							# print Data::Dumper->Dump([$sequence_map]); print "here\n"; exit;

							my $label = $sequence_map->{label};

							if (defined $sequence_map->{annotations} && 
										ref($sequence_map->{annotations}) eq 'HASH'){

	 							# print Data::Dumper->Dump([$sequence_map->{'annotations'}]); exit;
								for my $seq_feature (@{$sequence_map->{'annotations'}->{'seq_feature'}}){

									# print Data::Dumper->Dump([$seq_feature]); exit;
									my $seq_location = $seq_feature->{'seq_location'};
                                                                        my $start_coord = $seq_feature->{'least_start'};
                                                                        my $feature_type = $seq_feature->{'feature_type'};
                                                                        my $end_coord = $seq_feature->{'greatest_end'};
                                                                        my $is_on_complement = $seq_feature->{'is_on_complement'};


			                                                my $feat = Bio::SeqFeature::Generic->new(
                                                                                                                                             
			                                                                -start => $start_coord,
			                                                                -end => $end_coord,
			                                                                #-source_tag => $feature_name,
			                                                                #-display_name => $feature_name,
			                                                                -primary_tag => $feature_type,
			                                                );




									if (defined $seq_feature->{'qualifier'} && 
											ref($seq_feature->{'qualifier'}) eq 'ARRAY'){
									# print Data::Dumper->Dump([$seq_feature->{'qualifier'}]); exit;
										for my $feature (@{$seq_feature->{'qualifier'}}){
											
											my $value = $feature->{'qualifier'};
				                                                        my $feature_type = $feature->{'qualifier_type'};
				                                                        $feat->add_tag_value($feature_type => $value);
								
										}

							
									}

									 $seq->add_SeqFeature($feat);
#									 push @{$self->{'sequence_objects'}}, $seq;

								} # close for my $seq_feature (@{$sequence_map->...

							} # close if (defined $sequence_map->{annotations} &&

						} # close for my $sequence_map (@{$bio_sequence->{'sequence_map'}}){

					} # close if (defined $bio_sequence->{'sequence_map'}){


				#} # close for my $bio_sequence

				push @{$self->{'sequence_objects'}}, $seq;

			} # close for my $fragment_orientation

		} # close for my $fragment_order

	} # close for my $contig


	# Flag is set so that we know that the sequence objects are now stored in $self.
	$self->{'seqs_stored'} = 1;

}


=head2 next_seq

 Title   : next_seq
 Usage   : $seq = $stream->next_seq()
 Function: returns the next sequence in the stream
 Returns : Bio::Seq object
 Args    : NONE

=cut

sub next_seq {

	my ($self) = @_;

	# convert agave to genbank/fasta/embl whatever.
  
	$self->_store_seqs if $self->{'seqs_stored'} == 0;
	# print Data::Dumper->Dump([$self]); exit;
	die "_store_seqs not executed yet!" if !defined $self->{'sequence_objects'};
	if (scalar @{$self->{'sequence_objects'}} > 0){
		return shift @{$self->{'sequence_objects'}};
	} else {
		# All done.  Nothing more to parse.
		# print "returning nothing!\n";
		return 0;
	}


}


=head2 next_primary_seq

 Title   : next_primary_seq
 Usage   : $seq = $stream->next_primary_seq()
 Function: returns the next primary sequence (ie no seq_features) in the stream
 Returns : Bio::PrimarySeq object
 Args    : NONE

=cut

sub next_primary_seq {
  my $self=shift;
  return 0;
}


=head2 write_seq

 Title   : write_seq
 Usage   : Not Yet Implemented! $stream->write_seq(@seq)
 Function: writes the $seq object into the stream
 Returns : 1 for success and 0 for error
 Args    : Bio::Seq object

Convert embl/fasta/gb, whatever to agave.


=cut

sub write_seq {
  my ($self,@seqs) = @_;
  
  foreach my $seq ( @seqs ){
     $self->_write_each_record( $seq ) ;
  }
}

=head2 _write_each_record

 Title   : _write_each_record
 Usage   : $agave->_write_each_record( $seqI )
 Function: change data into agave format
 Returns : NONE
 Args    : Bio::SeqI object

=cut

sub  _write_each_record {
  my ($self,$seq) = @_;

  # $self->{'file'} =~ s/>//g;
  my $output = new IO::File(">" . $self->{'file'});
  my $writer = new XML::Writer(OUTPUT => $output,
  		               NAMESPACES => 0,
			       DATA_MODE => 1,
			       DATA_INDENT => 2 ) ;

  $writer->xmlDecl("UTF-8");
  $writer->doctype("sciobj", '', "sciobj.dtd");
  $writer ->startTag('sciobj',
                      'version', '2',
                       'release', '2');

  $writer->startTag('contig', 'length', $seq->length);
  my $annotation = $seq ->annotation;   # print "annotation: $annotation\n"; exit;  Bio::Annotation::Collection=HASH(0x8112e6c)
  if( $annotation->get_Annotations('dblink') ){ # used to be $annotation->each_DBLink, but Bio::Annotation::Collection::each_DBLink
                                                # is now replaced with get_Annotations('dblink')
      my $dblink = $annotation->get_Annotations('dblink')->[0] ;
                                                                                                                                             
      $writer ->startTag('db_id',
                     'id', $dblink->primary_id ,
                     'db_code', $dblink->database );
  }else{
      $writer ->startTag('db_id',
                     'id', $seq->display_id ,
                     'db_code', 'default' );
  }
  $writer ->endTag('db_id') ;


  $writer->startTag('fragment_order');
  $writer->startTag('fragment_orientation');

  ##start bio_sequence
  ####my $organism = $seq->species->genus . " " . $seq->species->species;
  $writer ->startTag('bio_sequence',
                     'sequence_id', $seq->display_id,
                     'seq_length', $seq->length,
                     # 'molecule_type', $seq->moltype, # deprecated
		     'molecule_type', $self->alphabet,
                     #'organism_name', $organism
  );
 
  # my $desc = $seq->{primary_seq}->{desc};
  # print "desc: $desc\n"; exit;
  # print Data::Dumper->Dump([$seq]);  exit;
  ##start db_id under bio_sequence
  $annotation = $seq ->annotation;	# print "annotation: $annotation\n"; exit;  Bio::Annotation::Collection=HASH(0x8112e6c)
  if( $annotation->get_Annotations('dblink') ){	# used to be $annotation->each_DBLink, but Bio::Annotation::Collection::each_DBLink 
  						# is now replaced with get_Annotations('dblink')
      my $dblink = $annotation->get_Annotations('dblink')->[0] ;
  
      $writer ->startTag('db_id',
                     'id', $dblink->primary_id ,
                     'db_code', $dblink->database );
  }else{
      $writer ->startTag('db_id',
                     'id', $seq->display_id ,
                     'db_code', 'default' );
  }
  $writer ->endTag('db_id') ;

  ##start note
  my $note = "" ;
  foreach my $comment ( $annotation->get_Annotations('comment') ) { # used to be $annotations->each_Comment(), but that's now been replaced
								    # with get_Annotations()
       # $comment is a Bio::Annotation::Comment object
       $note .= $comment->text() . "\n";
  }
  
  $writer ->startTag('note');
  $writer ->characters( $note ) ;
  $writer ->endTag('note');

  ##start description
  $writer ->startTag('description');

 # $writer ->characters( $annotation->get_Annotations('description') ) ; # used to be $annotations->each_description(), but that's now been
									# replaced with get_Annotations.
 # Simon added this: this is the primary_seq's desc (the DEFINITION tag in a genbank file)
 $writer->characters($seq->{primary_seq}->{desc});
 $writer ->endTag('description');

  ##start keywords
  foreach my $genename ( $annotation->get_Annotations('gene_name') ){  # used to be $annotations->each_gene_name, but that's now been
								       # replaced with get_Annotations()
      $writer ->startTag('keyword');
      $writer ->characters( $genename ) ;
      $writer ->endTag('keyword');
  }

  
  foreach my $ref ( $annotation->get_Annotations('reference') ) {	# used to be $annotation->each_Reference, but 
									# that's now been replaced with get_Annotations('reference');
      # link is a Bio::Annotation::Reference object
      $writer ->startTag('keyword');
      # print Data::Dumper->Dump([$ref]); exit;
	my $medline  = $ref->medline || 'null';
	my $pubmed   = $ref->pubmed || 'null';
	my $database = $ref->database || 'null';
	my $authors  = $ref->authors || 'null';
	my $title    = $ref->title || 'null';


      $writer ->characters( 'medline:' . "$medline" . ':' . 'pubmed:' . "$pubmed" . ':' . 'database:' . "$database" . ':' .'authors:' . "$authors" . ':' . 'title:' . "$title" ) ;
      $writer ->endTag('keyword');
  }

  ## start sequence
  $writer ->startTag('sequence');
  $writer ->characters( $seq->seq ) ;
  $writer ->endTag('sequence');
  
  ## start xrefs
  $writer ->startTag('xrefs');
  foreach my $link ( $annotation->get_Annotations('dblink') ) {
      # link is a Bio::Annotation::DBLink object
      $writer ->startTag('db_id',
                         'db_code', $link->database,
                         'id', $link->primary_id);
      $writer ->characters( $link->comment ) ;
      $writer ->endTag('db_id');
  }
  $writer ->endTag('xrefs') ;

  ##start sequence map
  ##we can not use :  my @feats = $seq->all_SeqFeatures;
  ##rather, we use top_SeqFeatures() to keep the tree structure
  my @feats = $seq->top_SeqFeatures ;
  
  my $features;
  
  ##now we need cluster top level seqfeature by algorithm
  my $maps;
  foreach my $feature (@feats) {
      my $map_type = $feature ->source_tag;
      push (@{$maps->{ $map_type }}, $feature);
  }

  ##now we enter each sequence_map  
  foreach my $map_type (keys  %$maps ){
      $writer->startTag('sequence_map',
                        'label', $map_type );
      $writer->startTag('annotations'); # the original author accidently entered 'annotation' instead of 'annotations'

      foreach my $feature ( @{$maps->{ $map_type }} ) {
          $self->_write_seqfeature( $feature, $writer ) ; 
      }

      $writer->endTag('annotations');
      $writer->endTag('sequence_map');
  }   
  
  $writer->endTag('bio_sequence');
  $writer->endTag('fragment_orientation');
  $writer->endTag('fragment_order');
  $writer->endTag('contig');
  $writer->endTag('sciobj');

}

=head2 _write_seqfeature

 Usage   : $agave->_write_each_record( $seqfeature, $write )
 Function: change seeqfeature data into agave format
 Returns : NONE
 Args    : Bio::SeqFeature object and XML::writer object

=cut
sub _write_seqfeature{
    my ($self,$seqf, $writer) = @_;
    
    ##now enter seq feature
    $writer ->startTag('seq_feature',
                       'feature_type', $seqf->primary_tag() );
    ##enter seq_location
    ### print "seqf: $seqf\n"; # exit; # Bio::SeqFeature::Generic=HASH(0x85e20a4)
    my $strand = $seqf->strand();
    $strand = 0 if !defined $strand;
    # $strand == 1 ? 'false' : 'true';
    my $is_on_complement;    
    if ($strand == 1){
	$is_on_complement = 'true';
    } else {
        $is_on_complement = 'false';
    }

   # die Data::Dumper->Dump([$seqf]) if !defined $strand;
    $writer ->startTag('seq_location',
                       'lease_start', $seqf->start(),
                       'greatest_end', $seqf->end(),
                       # 'is_on_complement', $seqf->strand() == 1 ? 'false' : 'true') ;
		       'is_on_complement' , $is_on_complement);
    # is_on_complement:  is the feature found on the complementary strand (true) or not (false)?
    $writer ->endTag('seq_location');
    
    ##enter qualifier
    
    foreach my $tag ( $seqf->all_tags() ) {
        $writer ->startTag('qualifier',
                      'qualifier_type', $tag);
        $writer ->characters( $seqf->each_tag_value($tag) ) ;
        $writer ->endTag('qualifier');
    }
    ##now recursively travel the seqFeature
    foreach my $subfeat ( $seqf->sub_SeqFeature ){
        $self->_write_seqfeature( $subfeat, $writer ) ;
    }
   
    $writer ->endTag('seq_feature');
}


=head2 _filehandle

 Title   : _filehandle
 Usage   : $obj->_filehandle($newval)
 Function:
 Example :
 Returns : value of _filehandle
 Args    : newvalue (optional)


=cut

sub _filehandle{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'_filehandle'} = $value;
    }
    return $obj->{'_filehandle'};

}

1;
