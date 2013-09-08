package MojoX::DirectoryListing;

use 5.010;
use strict;
use warnings FATAL => 'all';
use base 'Exporter';

our @EXPORT = ('serve_directory_listing');
our $VERSION = '0.01';
our $public_dir = "public";

sub set_public_app_dir {
    $public_dir = shift;
    $public_dir =~ s{/+$}{};
}

sub serve_directory_listing {
    $DB::single = 1;
    my $route = shift;
    my $local;
    if (@_ % 2 == 1) {
	$local = shift;
    }
    my %options = @_;
    my $caller = $options{caller} // caller;

    my $listing_sub = _mk_dir_listing($route,$local,%options);

    $caller->app->routes->get( $route, $listing_sub );

    if ($options{recursive}) {
	my $dh;
	my $actual = $local // $public_dir . $route;
	opendir $dh, $actual;
	my @subdirs = grep {
	    $_ ne '.' && $_ ne '..' && -d "$actual/$_"
	} readdir($dh);
	closedir($dh);
	$options{caller} //= $caller;
	my $route1 = $route eq '/' ? '' : $route;
	foreach my $subdir (@subdirs) {
	    if ($local) {
		serve_directory_listing( "$route1/$subdir",
					 "$local/$subdir", %options );
	    } else {
		serve_directory_listing( "$route1/$subdir", %options );
	    }
	}
    }

    if ($local) {
	$caller->app->routes->get( "$route/#file", 
				   _mk_fileserver($local) );
    }
}

sub _mk_fileserver {
    my ($local) = @_;
    return sub {
	my $self = shift;
	my $file = $self->param('file');

	if (! -r "$local/$file") {
	    $self->status(403);
	} elsif (-d "$local/$file") {
	    $self->status(403);
	} elsif (open my $fh, '<', "$local/$file") {
	    my $output = join '', <$fh>;
	    close $fh;
	    $self->render( text => $output );
	} else {
	    $self->status(404);
	}	
    };
}

sub _mk_dir_listing {
    my ($route, $local, %options) = @_;
    die "Expect leading slash in route $route"
	unless $route =~ m#^/#;
    $local //= $public_dir . $route;
    return sub {
	my $self = shift;
	$self->stash( "actual-dir", $local );
	$self->stash( "virtual-dir", $route );
	$self->stash( $_ => $options{$_} ) for keys %options;
	_render_directory( $self );
    };
}

sub _render_directory {
    my $self = shift;
    my $output;
    my $virtual_dir = $self->stash("virtual-dir");
    my $actual_dir = $self->stash("actual-dir");

    # sort column: [N]ame, Last [M]odified, [S]ize, [D]escription
    my $sort_column = $self->param('C') || $self->stash('sort-column') || 'N';

    # support Apache style  ?C=x;O=y  query string or ?C=x&O=y
    if ($sort_column =~ /^(\w);O=(\w)/) {
	$sort_column = $1;
	$self->param("O", $2);
    }
    # sort order: [A]scending, [D]escending
    my $sort_order = $self->param('O') || $self->stash('sort-order') || 'A';

    my $show_file_time = $self->stash("show-file-time") // 1;
    my $show_file_size = $self->stash("show-file-size") // 1;
    my $show_file_type = $self->stash("show-file-type") // 1;
    my $show_forbidden = $self->stash("show-forbidden") // 0;

    # XXX - what else is configurable ?
    #     <head></head> section
    #     page header
    #     page footer
    #     css
    my $header = $self->stash("header") // "-";
    my $page_header = $self->stash("page-header") // "-";

    $virtual_dir =~ s{/$}{} unless $virtual_dir eq '/';
    my $dh;
    if (!opendir $dh, $actual_dir) {
	print STDERR "opendir failed on $actual_dir ???\n";
	die;
    }
    my @items = map {
	my @stat = stat("$actual_dir/$_");
	my $modtime = $stat[9];
	my $size = $stat[7];
	my $is_dir = -d "$actual_dir/$_";
	$size = -1 if $is_dir;
	my $forbidden = ! -r "$actual_dir/$_";
	+{
	    name => $_,
	    is_dir => $is_dir,
	    modtime => $modtime,
	    size => $size,
	    forbidden => $forbidden,
	    type => $is_dir ? "Directory" : _filetype("$_")
	};
    } readdir($dh);
    closedir $dh;

    if ($sort_column eq 'S') {
	@items = sort { $a->{size} <=> $b->{size} 
			|| $a->{name} cmp $b->{name} } @items;
    } elsif ($sort_column eq 'M') {
	@items = sort { $a->{modtime} <=> $b->{modtime} 
			|| $a->{name} cmp $b->{name} } @items;
    } elsif ($sort_column eq 'T') {
	@items = sort { $a->{type} cmp $b->{type} 
			|| $a->{name} cmp $b->{name} } @items;
    } else {
	@items = sort { $a->{name} cmp $b->{name} } @items;
    }
    if ($sort_order eq 'D') {
	@items = reverse @items;
    }

    $output = "<!DOCTYPE html><html><head>";

    if ($header ne '-' && open my $fh, '<', $header) {
	$output .= join '', <$fh>;
	close $fh;
    } else {
    $output .= <<'__END_DEFAULT_HEAD__';
<style>

body     { font-family: "Lucida Grande", tahoma, sans-serif;
           font-size: 100%; margin: 0; width: 100%; }
h1 {
	background: #999;
	background: -webkit-gradient(linear, left top, left bottom, from(#A2C6E
5), to(#2B6699));
	background: -moz-linear-gradient(top,  #A2C6E5,  #2B6699);
	filter: progid:DXImageTransform.Microsoft.gradient(startColorstr='#A2C6
E5', endColorstr='#2B6699');
	padding: 10px 0 10px 10px; margin: 0; color: white;
}
li.dir a { font-weight: bold; font-size: 1.1em;	color: #346D9E; }
a        { color: #5C8DB8; }
hr       { border: solid silver 1px; width: 95%; }
.directory-listing-row, .directory-listing-header { font-family: Courier }

</style>
__END_DEFAULT_HEAD__
    }

    $output .= qq[</head><body><base href="/" />\n];
    $output .= qq{<!-- directory listing by MojoX::DirectoryListing -->\n};

    # default page header
    $output .= "<h1>$virtual_dir</h1>\n";
    $output .= "<hr />\n";


    $output .= "<table border=0>\n";
    $output .= qq!<thead class="directory-listing-header">\n!;
    for ( [1,'Name','N'], [$show_file_time,'Last Modified','M'], 
	  [$show_file_size,'Size','S'], [$show_file_type,'Type','T'] ) {
	my ($show, $text, $col_code) = @$_;
	next if !$show;
	my $sortind = "";
	my $order_code = 'A';
	if ($sort_column eq $col_code) {
	    if ($sort_order eq 'D') {
		$sortind = "v";
	    } else {
		$sortind = "^";
		$order_code = 'D';
	    }
	}

	$output .= qq{<th><a href="$virtual_dir?C=$col_code;O=$order_code">};
	$output .= qq{$text</a> $sortind</th>\n};
    }
    $output .= "</thead>\n";
    $output .= "<tbody>\n";

    foreach my $item (@items) {
        next if $item->{name} eq '.';
        next if $item->{forbidden} && !$show_forbidden;
        $output .= "<tr class=\"directory-listing-row\">\n";
	if ($item->{forbidden}) {
	    $output .= "  <td class=\"directory-listing-forbidden-name\">$item->{name}</td>\n";
	} else {
	    $output .= "  <td class=\"directory-listing-name\">";
	    $output .= "<a href=\"$virtual_dir/$item->{name}\">";
	    $output .= "<strong>" . $item->{name} . "</strong></a></td>\n";
	}
	if ($show_file_time) {
	    $output .= "  <td class=\"directory-listing-time\">";
	    $output .= "&nbsp;" . _render_modtime($item->{modtime});
	    $output .= "&nbsp;</td>\n";
	}
	if ($show_file_size) {
	    $output .= "  <td class=\"directory-listing-size\">";
	    $output .= "&nbsp;" . _render_size($item);
	    $output .= "&nbsp;</td>\n";
	}
	if ($show_file_type) {
	    $output .= "  <td class=\"directory-listing-type\">";
	    $output .= "&nbsp;" . $item->{type};
	    $output .= "&nbsp;</td>\n";
	}
	$output .= "</tr>\n";
    }
    $output .= "</tbody></table>\n";

    # XXX - footer

    $output .= "</body></html>\n";
    $self->render( text => $output );
}

sub _render_size {
    my $item = shift;
    if ($item->{is_dir}) {
	return "--";
    }
    my $s = $item->{size};
    if ($s < 100000) {
	return $s;
    }
    if ($s < 1024 * 999.5) {
	return sprintf "%.3gK", $s/1024;
    }
    if ($s < 1024 * 1024 * 999.5) {
	return sprintf "%.3gM", $s/1024/1024;
    }
    if ($s < 1024 * 1024 * 1024 * 999.5) {
	return sprintf "%.3gG", $s/1024/1024/1024;
    }
    return sprintf "%.3gT", $s/1024/1024/1024/1024;
}

sub _render_modtime {
    my $t = shift;
    my @gt = localtime($t);
    sprintf ( "%04d-%s-%02d %02d:%02d:%02d",
	      $gt[5]+1900,
	      [qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)]->[$gt[4]],
	      @gt[3,2,1,0] );
}

sub _filetype {
    my $file = shift;
    if ($file =~ s/.*\.//) {
	return $file;
    }
    return "Unknown";
}

1;
  
=head1 NAME

MojoX::DirectoryListing - show Apache-style directory listings in your Mojolicious app

=head1 VERSION

0.01

=head1 SYNOPSIS

    use Mojolicious;  # or Mojolicious::Lite;
    use MojoX::DirectoryListing;

    # serve a directory listing under your app's  public/  folder
    serve_directory_listing( '/data' );

    # serve a directory listing in a different location
    serve_directory_listing( '/more-data', '/path/to/other/directory' );

    # serve all subdirectories, too
    serve_directory_listing( '/data', recursive => 1 );

    # change the default display options
    serve_directory_listings( '/data', 'show-file-type' => 0, 'show-forbidden' => 1 );

=head1 DESCRIPTION

I ported a web application from CGI to L<Mojolicious>. I was mostly pleased
with the results, but one of the features I lost in the port was the ability
to serve a directory listing. This module is an attempt to make that feature
available in Mojolicious, and maybe even make it better.

Mojolicious serves static files under your app's C<public/> directory.
To serve a whole directory under your C<public/> directory (say, 
C<public/data-files>), you would call

    serve_directory_listings( '/data-files' );

Now a request to your app for C</dara-files> will display a listing
of all the files under C<public/data-files> .

To serve a directory listing for a directory that is B<not> under
your app's public directory, provide a second argument to
C<serve_directory_listings>. For example

    serve_directory_listings( '/research', 'public/files/research/public' );
    serve_directory_listings( '/log', '/var/log/system' );

=head1 EXPORT

This module exports the L<"serve_directory_listing"> subroutine
to the calling package.

=head1 SUBROUTINES/METHODS

=head2 serve_directory_listing

=head2 serve_directory_listing( $route, %options )

=head2 serve_directory_listing( $route, $path, %options )

Configures the Mojolicious app to serve directory listings
for the specified path rom the specified route.

If C<$path> is omitted, then the appropriate directory
in your apps C<public> directory will be listed. For example,
the route C</data/foo> will serve a listing for your app's
C<public/data/foo> directory.

=head3 recognized options

The C<serve_directory_listing> function recognizes several options
that control the appearance and the behavior of the directory listing.

=over 4

=item C<sort-column> => C< N | M | S | T >

Controls whether the files in a directory will be ordered
by C<< <N> >>ame, file C<< <M> >>odification time,
file C<< <S> >>ize, or file C<< <T> >>ype.
The default is to order listings by name. 

If a request includes the parameter C<C>, it will override
this setting for that request. This makes the behavior of
this feature similar to the feature in Apache (see
L<http://www2.census.gov/geo/tiger/GENZ2010/?C=M;O=A>,
for example.

=item C<display-order> => C< A | D>

Controls whether the files will be listed
(using the sort criteria from C<sort-column>)
in C<< <A> >>scending or C<< <D> >>escending order.
The default is ascending order.

A request that includes the parameter C<O> will override
this setting for that request.    

=item C<show-file-time> => boolean

If true, the directory listing includes the modification time
of each file listed. The default is true.

=item C<show-file-size> => boolean

If true, the directory listing includes the size of each file
listed. The default is true.

=item C<show-file-type> => boolean

If true, the directory listing includes the MIME type of each
file listed. The default is true.

=item C<show-forbidden> => boolean

If true, the directory listing includes files that are not
readable by the user running the web server. When such a 
file is listed, it will not include a link to the file.
The default is false.

=item C<recursive> => boolean

If true, invoke C<serve_directory_listing> on all
I<subdirectories> of the directory being served.
The default is false.

=back

=head2 set_public_app_dir( $path )

Tells C<MojoX::DirectoryListing> which directory your
app uses to serve static data. The default is C<./public>.
The public app dir is used to map the route to an actual
path when you don't supply a C<$path> argument to
L<"serve_directory_listing">.

=head1 TODO

There are a lot of ways this module could be more powerful and more
useful:

=over 4

=item * user-configurable page header

=item * user-configurable page footer

=item * flesh out and document classes that can be
styled with CSS

=back

=head1 AUTHOR

Marty O'Brien, C<< <mob at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to 
C<bug-mojox-lite-directorylisting at rt.cpan.org>, or through
the web interface at 
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=MojoX-DirectoryListing>.  
I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc MojoX::DirectoryListing


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=MojoX-DirectoryListing>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/MojoX-DirectoryListing>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/MojoX-DirectoryListing>

=item * Search CPAN

L<http://search.cpan.org/dist/MojoX-DirectoryListing/>

=back


=head1 ACKNOWLEDGEMENTS

github user L<Glenn Hinkle|https://github.com/tempire>
created the L<app-dirserve|https://github.com/tempire/app-dirserve>
microapplication to serve a directory over a webservice. 
I have borrowed a lot of his ideas and a little of 
his code in this module.

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Marty O'Brien.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of MojoX::DirectoryListing
