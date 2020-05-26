package Thruk::Controller::woshsh;

use strict;
use warnings;

=head1 NAME

Thruk::Controller::woshsh - Thruk Controller

=head1 DESCRIPTION

Thruk Controller.

=head1 METHODS

=cut

BEGIN {
    #use Thruk::Timer qw/timing_breakpoint/;
}

use Spreadsheet::ParseExcel;
use Spreadsheet::WriteExcel;
use File::Temp qw/tempfile/;
use File::Copy qw/move/;
use Carp qw/confess/;
use Cpanel::JSON::XS qw/decode_json/;
use Thruk::Utils::IO;

##########################################################

=head2 index

=cut
sub index {
    my ( $c ) = @_;

    #&timing_breakpoint('woshsh::index');
    return unless Thruk::Action::AddDefaults::add_defaults($c, Thruk::ADD_CACHED_DEFAULTS);

    $c->stash->{readonly}        = 0;
    $c->stash->{title}           = 'Woshsh';
    $c->stash->{'extjs_version'} = "6.0.1";

    $c->stash->{'is_admin'} = 0;
    if($c->check_user_roles('authorized_for_system_commands') && $c->check_user_roles('authorized_for_configuration_information')) {
        $c->stash->{'is_admin'} = 1;
    }

    my $files = Thruk::Utils::list($c->config->{'Thruk::Plugin::woshsh'}->{'input_file'});
    $c->stash->{'files'} = $files;
    $c->stash->{'selected_file'} = $c->req->parameters->{'file'} || $files->[0];

    if(!$files || scalar @{$files} == 0) {
        $c->stash->{errorMessage}       = "no <b>input_files</b> defined.";
        $c->stash->{errorDescription}   = "plugin requires input_files, see <a href='https://github.com/sni/thruk-plugin-woshsh'>README</a> for setup instructions.";
        return $c->detach('/error/index/99');
        return;
    }

    if(defined $c->req->parameters->{'save'}) {
        my $excel_data = _read_data_file($c, $c->stash->{'selected_file'});
        my $worksheet  = _get_worksheet($excel_data, $c->req->parameters->{'name'});
        my $val        = decode_json($c->req->parameters->{values});
        my $removed    = Thruk::Config::array2hash(decode_json($c->req->parameters->{removed}));
        for my $v (@{$val}) {
            my $row = $v->{'row'};
            delete $v->{'data'}->{'id'};
            $worksheet->[1]->{'data'}->[$row] = $v->{'data'};
        }

        if(scalar keys %{$removed} > 0) {
            for my $s (@{$excel_data}) {
                next unless $s->[0] eq $c->req->parameters->{'name'};
                my @to_remove = sort {$b <=> $a} keys %{$removed};
                my @data = @{$s->[1]->{'data'}};
                my $next = shift @to_remove;
                for(my $i = scalar @data -1; $i >= 0; $i--) {
                    if(defined $next && $i == $next) {
                        splice(@{$s->[1]->{'data'}}, $i, 1);
                        $next = shift @to_remove;
                    }
                }
            }
        }


        # save excel file
        my($fh, $tempfile) = tempfile();
        my $workbook = Spreadsheet::WriteExcel->new($tempfile);
        for my $s (@{$excel_data}) {
            my $sheet = $workbook->add_worksheet($s->[0]);
            my $ro = 0;
            for my $row (@{$s->[1]->{'data'}}) {
                my $co = 0;
                for my $n (@{$worksheet->[1]->{'metaData'}->{'columns'}}) {
                    $sheet->write($ro, $co, $row->{$n->{'dataIndex'}});
                    $co++;
                }
                $ro++;
            }
        }
        $workbook->close();
        move($tempfile, $c->stash->{'selected_file'});
        # update cache file
        my $cache_file = _get_cache_file_name($c, $c->stash->{'selected_file'});
        Thruk::Utils::IO::json_lock_store($cache_file, $excel_data);
        return $c->render(json => { ok => 1 });
    }
    if(defined $c->req->parameters->{'load'}) {
        my $excel_data = _read_data_file($c, $c->stash->{'selected_file'});
        my $worksheet  = _get_worksheet($excel_data, $c->req->parameters->{'name'});
        return $c->render(json => $worksheet->[1]);
    }

    $c->stash->{'worksheets'} = _get_worksheets($c, $c->stash->{'selected_file'});

    $c->stash->{template} = 'woshsh.tt';
    return 1;
}

##########################################################
sub _read_data_file {
    my($c, $file) = @_;

    my $cache_file = _get_cache_file_name($c, $file);
    my $data;
    if(!-f $cache_file) {
        $data = _parse_excel_file($c, $file);
        Thruk::Utils::IO::json_lock_store($cache_file, $data);
    } else {
        my @stat1 = stat($file);
        my @stat2 = stat($cache_file);
        if($stat1[9] > $stat2[9]) {
            $data = _parse_excel_file($c, $file);
            Thruk::Utils::IO::json_lock_store($cache_file, $data);
        } else {
            $data = Thruk::Utils::IO::json_lock_retrieve($cache_file);
        }
    }

    return($data) if $data;
    confess("no such file / worksheet");
}

##########################################################
sub _parse_excel_file {
    my($c, $file) = @_;

    my $parser = Spreadsheet::ParseExcel->new();
    my $data   = [];

    my $workbook = $parser->parse($file);
    if(!defined $workbook) {
        confess($file.': '.$parser->error());
    }
    for my $worksheet ( $workbook->worksheets() ) {
        my $worksheet_data = {
            metaData => {
                fields  => [header => "_row", dataIndex => "_row"],
                columns => [],
            },
            data    => [],
        };
        my ( $row_min, $row_max ) = $worksheet->row_range();
        my ( $col_min, $col_max ) = $worksheet->col_range();
        for my $row ($row_min .. $row_max) {
            my $row_data = {"_row" => $row};
            for my $col ( $col_min .. $col_max ) {
                my $cell = $worksheet->get_cell( $row, $col );
                next unless $cell;
                $row_data->{chr($col+65)} = $cell->value();
            }
            push @{$worksheet_data->{'data'}}, $row_data;
        }
        for my $x (65..90) {
            push @{$worksheet_data->{'metaData'}->{'columns'}}, { header => chr($x), dataIndex => chr($x) };
            push @{$worksheet_data->{'metaData'}->{'fields'}},  { name   => chr($x), type      => "string" };
        }
        push @{$data}, [ $worksheet->get_name(), $worksheet_data ];
    }

    return($data);
}

##########################################################
sub _get_worksheet {
    my($data, $name) = @_;
    for my $worksheet (@{$data}) {
        if($worksheet->[0] eq $name) {
            return($worksheet);
        }
    }
    confess("no such file / worksheet");
}

##########################################################
sub _get_worksheets {
    my($c, $file) = @_;
    my $excel_data = _read_data_file($c, $file);
    my @sheets;
    for my $worksheet (@{$excel_data}) {
        push @sheets, $worksheet->[0];
    }
    return(\@sheets);
}

##########################################################
sub _get_cache_file_name {
    my($c, $file) = @_;
    my $cache_file = $file;
    $cache_file =~ s%^.*/%%gmx;
    $cache_file = $c->config->{'tmp_path'}."/woshsh/".$cache_file;
    Thruk::Utils::IO::mkdir_r($c->config->{'tmp_path'}."/woshsh");
    return($cache_file);
}

##########################################################

=head1 AUTHOR

Sven Nierlein, 2009-present, <sven@nierlein.org>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
