use Test::More;
use Test::Mojo;
use MojoX::DirectoryListing;
use strict;
use warnings;

diag 'building test filesystem';
mkdir "t/app1/private";
open my $fh_HTML, '>', 't/app1/private/img.html';
print $fh_HTML "<html><head><title>Hey!</title></head>";
print $fh_HTML "<body>How are you?</body></html>";
close $fh_HTML;
open my $fh_TXT, '>', 't/app1/private/img.txt';
print $fh_TXT "This is t/app1/private/img.txt\n";
close $fh_TXT;
open my $fh_GIF, '>:raw', 't/app1/private/img.gif';
print $fh_GIF "GIF89a\025\0\004\0\200\0\0#-0\377\377\377!\371\004\001\0\0";
print $fh_GIF "\001\0,\0\0\0\0\025\0\004\0\0\002\r\214\037\240\013\350\317";
print $fh_GIF "\332\233g\321k\$-\0;";
close $fh_GIF;
open my $fh_PNG, '>:raw', 't/app1/private/img.png';
print $fh_PNG "\231PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\001\0\0\001\220\b\006";
print $fh_PNG "\0\0\0oX\n \024\303\320\355\337\377\314+\026\t\212\204\314";
print $fh_PNG "\274\244\242J\302HR)\345[lk\200=O_\340\362(\245<`\001\344";
print $fh_PNG "\264\r\033H\343\"\264\0\0\0\0IEND\256B`\202";
close $fh_PNG;

open my $fh_XYZ, '>:raw', 't/app1/private/img.xyz';
print $fh_XYZ chr($_) for 0..255;
close $fh_XYZ;
open my $fh_ABC, '>', 't/app1/private/img.abc';
print $fh_ABC 
      "This is a text file, but you can't tell that from the extension.\n";
close $fh_ABC;
open my $fh_NONE, '>', 't/app1/private/somefile';
print $fh_NONE chr(255-$_) for 0..255;
close $fh_NONE;



mkdir "t/app1/public";

END {
    diag 'tearing down test filesystem';
    unlink glob("t/app1/private/*");
    rmdir "t/app1/private";
    rmdir "t/app1/public";
}

# Server6 serves non-public files from t/app1/private
my $t6 = Test::Mojo->new( 't::app1::Server6' );

$t6->get_ok('/test')->content_is('Server6', 'Server6 active');
$t6->get_ok('/hidden')->status_is(200)
    ->content_like( qr/directory listing by MojoX::DirectoryListing/ );
$t6->get_ok('/hidden/img.html')->status_is(200)
    ->content_like( qr/head.*body/is )
    ->content_type_like( qr'text/html' );
$t6->get_ok('/hidden/img.txt')->status_is(200)
    ->content_like( qr/This is t.app1.private.img.txt/ )
    ->content_type_like( qr'text/plain' );
$t6->get_ok('/hidden/img.abc')->status_is(200)
    ->content_type_like( qr/text/, 'text type detected from content' );
$t6->get_ok('/hidden/img.xyz')->status_is(200)
    ->content_type_like( qr#text/html#, 'default type is text/html' );
$t6->get_ok('/hidden/somefile')->status_is(200)
    ->content_type_like( qr#text/html#, 'default type is text/html' );

done_testing();
