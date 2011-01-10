use strict;
use warnings;
use Test::More;
use Plack::Test;
use HTTP::Request;
use HTTP::Request::Common;
use XML::LibXML;
use XML::Compile::SOAP::PSGI;

my $app = XML::Compile::SOAP::PSGI->new(
        wsdl_file   => 'wsdl/foo.wsdl',
        impl_object => undef,
);

test_psgi $app => sub {
        my ($cb) = @_;

        subtest 'good request' => sub {
                my $req = GET('/?wsdl');
                my $res = $cb->($req);
                ok($res->is_success, 'status');
                
                my $parser = XML::LibXML->new;
                my $doc = $parser->load_xml( string => $res->content );
                isa_ok($doc, 'XML::LibXML::Document', 'parsed xml');

                done_testing;
        };
};

done_testing;
