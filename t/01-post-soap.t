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
        impl_object => TestImpl->new,
);

test_psgi $app => sub {
        my ($cb) = @_;

        subtest 'good request' => sub {
                my $req = POST('/');
                my $soap = <<EOSOAP;
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                  xmlns:urn="urn:ComplexApp">
   <soapenv:Header/>
   <soapenv:Body>
      <urn:GoodRequest>
         <urn:email>foo</urn:email>
         <urn:password>bar</urn:password>
         <urn:id>1235</urn:id>
      </urn:GoodRequest>
   </soapenv:Body>
</soapenv:Envelope>
EOSOAP
                $req->content($soap);
                $req->headers->header( 'content-length' => length $soap );
                $req->headers->header( 'content-type'   => 'text/xml' );
                $req->headers->header( 'SOAPAction'     => 'urn:ComplexApp#Good' );

                my $res = $cb->($req);
                ok($res->is_success, 'status');
                
                my $parser = XML::LibXML->new;
                my $doc = $parser->load_xml( string => $res->content );
                isa_ok($doc, 'XML::LibXML::Document', 'parsed xml');

                done_testing;
        };

        subtest 'bad request' => sub {
                my $req = POST('/');
                my $soap = <<EOSOAP;
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                  xmlns:urn="urn:ComplexApp">
   <soapenv:Header/>
   <soapenv:Body>
      <urn:GoodRequest>
          <!-- missing data -->
      </urn:GoodRequest>
   </soapenv:Body>
</soapenv:Envelope>
EOSOAP
                $req->content($soap);
                $req->headers->header( 'content-length' => length $soap );
                $req->headers->header( 'content-type'   => 'text/xml' );
                $req->headers->header( 'SOAPAction'     => 'urn:ComplexApp#Good' );

                my $res = $cb->($req);
                ok($res->is_error, 'status');
                
                my $parser = XML::LibXML->new;
                my $doc = $parser->load_xml( string => $res->content );
                isa_ok($doc, 'XML::LibXML::Document', 'parsed xml');

                done_testing;
        };
};

done_testing;

package TestImpl;

sub new {
        return bless {}, shift;
}

sub Good {
        return { result => 1 };
}

1;
