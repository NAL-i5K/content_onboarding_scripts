#!/usr/bin/env perl
# This script was generated with GPT-5.3-Codex.
use strict;
use warnings;
use Getopt::Long;

my $usage = qq{
Usage:
    perl $0 --gff input.gff3 --gaf input.gaf.tsv --gmt input.gmt [--egap] [--cds] [--out output.gff3]

Required:
  --gff      Input GFF3 file
  --gaf      Input GAF 2.2 file
  --gmt      Input GMT file (PathAnnotator format)

Optional:
    --egap     Set this flag if the GFF3 uses EGAP-style matching via CDS protein_id.
    --cds      Also add Ontology_term attributes to CDS features.
  --out      Output GFF3 file (default: <input>.with_ontology_terms.gff3)
  --help     Print this help text
};

my ($gff_file, $gaf_file, $gmt_file, $out_file, $is_egap, $annotate_cds, $help);
GetOptions(
    'gff=s'    => \$gff_file,
    'gaf=s'    => \$gaf_file,
    'gmt=s'    => \$gmt_file,
    'out=s'    => \$out_file,
        'egap!'    => \$is_egap,
        'cds!'     => \$annotate_cds,
    'help|h'   => \$help,
) or die $usage;

if ($help) {
    print $usage;
    exit 0;
}

die $usage unless defined $gff_file && defined $gaf_file && defined $gmt_file;

if (!defined $out_file) {
    $out_file = $gff_file . '.with_ontology_terms.gff3';
}


my %terms_by_key;
my $custom_pragma = '##Gene Ontology (GO) annotations are derived from GOAnna and InterProScan. KEGG, Reactome, and FlyBase pathway annotations are derived from PathAnnotator. For more information about the functional annotation protocol, see https://dx.doi.org/10.17504/protocols.io.dm6gp7n6jgzp/v1';
load_gaf_terms($gaf_file, \%terms_by_key);
load_gmt_terms($gmt_file, \%terms_by_key);

my %warned_prefixed_protein_ids;

my %mrna_to_proteins;
if ($is_egap) {
    build_mrna_to_protein_map($gff_file, \%mrna_to_proteins);
}

open(my $IN,  '<', $gff_file) or die "Cannot open $gff_file: $!\n";
open(my $OUT, '>', $out_file) or die "Cannot open $out_file: $!\n";

my $inserted_custom_pragma = 0;
my $mrna_updated = 0;
my $cds_updated  = 0;

while (my $line = <$IN>) {
    chomp $line;

    if ($line =~ /^#/) {
        print {$OUT} "$line\n";
        next;
    }

    if (!$inserted_custom_pragma) {
        print {$OUT} "$custom_pragma\n";
        $inserted_custom_pragma = 1;
    }

    my @f = split /\t/, $line, 9;
    if (@f < 9) {
        print {$OUT} "$line\n";
        next;
    }

    my $type = $f[2];
    my $attr = $f[8];
    my @terms_to_add;

    if ($is_egap) {
        if ($type eq 'mRNA') {
            my ($mrna_id) = get_attribute_values($attr, 'ID');
            if (defined $mrna_id && exists $mrna_to_proteins{$mrna_id}) {
                my %seen;
                foreach my $pid (@{$mrna_to_proteins{$mrna_id}}) {
                    my $match_pid = normalize_refseq_protein_id_for_match($pid, \%warned_prefixed_protein_ids);
                    next unless exists $terms_by_key{$match_pid};
                    foreach my $term (@{$terms_by_key{$match_pid}}) {
                        next if $seen{$term}++;
                        push @terms_to_add, $term;
                    }
                }
            }
            elsif (my ($mrna_pid) = get_attribute_values($attr, 'protein_id')) {
                my $match_pid = normalize_refseq_protein_id_for_match($mrna_pid, \%warned_prefixed_protein_ids);
                if (exists $terms_by_key{$match_pid}) {
                    @terms_to_add = @{$terms_by_key{$match_pid}};
                }
            }
        }
        elsif ($annotate_cds && $type eq 'CDS') {
            my ($pid) = get_attribute_values($attr, 'protein_id');
            my $match_pid = normalize_refseq_protein_id_for_match($pid, \%warned_prefixed_protein_ids);
            if (defined $match_pid && exists $terms_by_key{$match_pid}) {
                @terms_to_add = @{$terms_by_key{$match_pid}};
            }
        }
    }
    else {
        if ($type eq 'mRNA') {
            my ($mrna_id) = get_attribute_values($attr, 'ID');
            if (defined $mrna_id && exists $terms_by_key{$mrna_id}) {
                @terms_to_add = @{$terms_by_key{$mrna_id}};
            }
        }
        elsif ($annotate_cds && $type eq 'CDS') {
            my @parents = get_attribute_values($attr, 'Parent');
            my %seen;
            foreach my $parent (@parents) {
                next unless exists $terms_by_key{$parent};
                foreach my $term (@{$terms_by_key{$parent}}) {
                    next if $seen{$term}++;
                    push @terms_to_add, $term;
                }
            }
        }
    }

    if (@terms_to_add) {
        my $new_attr = add_ontology_terms($attr, \@terms_to_add);
        if ($new_attr ne $attr) {
            $f[8] = $new_attr;
            if ($type eq 'mRNA') {
                $mrna_updated++;
            }
            elsif ($type eq 'CDS') {
                $cds_updated++;
            }
        }
    }

    print {$OUT} join("\t", @f) . "\n";
}

close $IN;

if (!$inserted_custom_pragma) {
    print {$OUT} "$custom_pragma\n";
}

close $OUT;

warn "Wrote $out_file\n";
warn "Updated Ontology_term on $mrna_updated mRNA features and $cds_updated CDS features\n";


sub load_gaf_terms {
    my ($file, $terms_href) = @_;

    open(my $GAF, '<', $file) or die "Cannot open $file: $!\n";
    while (my $line = <$GAF>) {
        chomp $line;
        next if $line =~ /^!/;
        next if $line =~ /^\s*$/;

        my @c = split /\t/, $line;
        next unless @c >= 10;

        my $key    = $c[1];
        my $go_id  = $c[4];
        next unless defined $key && defined $go_id;
        next if $key eq '' || $go_id eq '';

        add_term_for_key($terms_href, $key, $go_id);
    }
    close $GAF;
}


sub load_gmt_terms {
    my ($file, $terms_href) = @_;

    my %db_map = (
        'FlyBase_pathway'        => 'FlyBase',
        'KEGG_reference_pathway' => 'KEGG',
        'KEGG_species_pathway'   => 'KEGG',
        'Reactome_pathway'       => 'Reactome',
    );

    open(my $GMT, '<', $file) or die "Cannot open $file: $!\n";
    while (my $line = <$GMT>) {
        chomp $line;
        next if $line =~ /^\s*$/;

        my @c = split /\t/, $line;
        next unless @c >= 4;

        my $path_id = $c[0];
        my $db_raw  = $c[1];
        my $db_prefix = $db_map{$db_raw};
        next unless defined $db_prefix;
        next unless defined $path_id && $path_id ne '';

        my $term = $db_prefix . ':' . $path_id;
        for (my $i = 2; $i < @c; $i++) {
            my $member = $c[$i];
            next unless defined $member;
            $member =~ s/^\s+//;
            $member =~ s/\s+$//;
            next if $member eq '';
            add_term_for_key($terms_href, $member, $term);
        }
    }
    close $GMT;
}


sub build_mrna_to_protein_map {
    my ($gff, $map_href) = @_;

    open(my $GFF, '<', $gff) or die "Cannot open $gff: $!\n";
    while (my $line = <$GFF>) {
        chomp $line;
        next if $line =~ /^#/;

        my @f = split /\t/, $line, 9;
        next unless @f >= 9;
        next unless $f[2] eq 'CDS';

        my $attr = $f[8];
        my ($pid) = get_attribute_values($attr, 'protein_id');
        next unless defined $pid && $pid ne '';
        $pid = normalize_refseq_protein_id_for_match($pid, \%warned_prefixed_protein_ids);

        my @parents = get_attribute_values($attr, 'Parent');
        foreach my $parent (@parents) {
            next unless defined $parent && $parent ne '';
            push @{$map_href->{$parent}}, $pid;
        }
    }
    close $GFF;

    foreach my $mrna_id (keys %{$map_href}) {
        my %seen;
        my @uniq = grep { !$seen{$_}++ } @{$map_href->{$mrna_id}};
        $map_href->{$mrna_id} = \@uniq;
    }
}


sub add_term_for_key {
    my ($terms_href, $key, $term) = @_;

    $terms_href->{$key} ||= [];
    my %seen = map { $_ => 1 } @{$terms_href->{$key}};
    if (!$seen{$term}) {
        push @{$terms_href->{$key}}, $term;
    }
}


sub normalize_refseq_protein_id_for_match {
    my ($pid, $warned_href) = @_;
    return $pid unless defined $pid;

    if ($pid =~ /^gnl\|WGS:\w+\|(.+)$/) {
        my $normalized = $1;
        if (!$warned_href->{__wgs_prefix_notice_shown__}) {
            $warned_href->{__wgs_prefix_notice_shown__} = 1;
            warn "Detected RefSeq protein_id prefix gnl|WGS:<token>|. This warning will only be shown once; all subsequent matching IDs will be normalized for matching (output keeps original protein_id values).\n";
        }
        return $normalized;
    }

    return $pid;
}


sub get_attribute_values {
    my ($attr, $target_key) = @_;
    my @values;

    my @parts = split /;/, $attr;
    foreach my $part (@parts) {
        next unless $part =~ /^([^=]+)=(.*)$/;
        my ($k, $v) = ($1, $2);
        next unless $k eq $target_key;

        my @vparts = split /,/, $v;
        foreach my $vp (@vparts) {
            next unless defined $vp;
            $vp =~ s/^\s+//;
            $vp =~ s/\s+$//;
            next if $vp eq '';
            push @values, $vp;
        }
    }

    return @values;
}


sub add_ontology_terms {
    my ($attr, $new_terms_aref) = @_;

    my @parts = grep { $_ ne '' } split /;/, $attr;
    my @existing_terms;
    my @other_parts;
    my $found_ontology = 0;
    my $ontology_term_count = 0;

    foreach my $part (@parts) {
        if ($part =~ /^Ontology_term=(.*)$/ && !$found_ontology) {
            $ontology_term_count++;
            $found_ontology = 1;
            my $v = $1;
            @existing_terms = grep { $_ ne '' } split /,/, $v;
        }
        elsif ($part =~ /^Ontology_term=/) {
            $ontology_term_count++;
        }
        elsif ($part !~ /^Ontology_term=/) {
            push @other_parts, $part;
        }
    }

    if ($ontology_term_count > 1) {
        warn "Found $ontology_term_count Ontology_term attributes in one feature; refusing to continue. Attribute string: $attr\n";
        die "Aborting because multiple Ontology_term attributes are not supported\n";
    }

    my %seen;
    my @merged;
    foreach my $t (@existing_terms) {
        next if $seen{$t}++;
        push @merged, $t;
    }
    foreach my $t (@{$new_terms_aref}) {
        next if $seen{$t}++;
        push @merged, $t;
    }

    push @other_parts, 'Ontology_term=' . join(',', @merged) if @merged;
    return join(';', @other_parts);
}
