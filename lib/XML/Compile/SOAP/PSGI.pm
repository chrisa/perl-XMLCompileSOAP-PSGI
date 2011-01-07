package XML::Compile::SOAP::PSGI;
use strict;
use warnings;

require 5.008_001;

our $VERSION = '0.01_01';
$VERSION = eval $VERSION;

=head1 NAME

XML::Compile::SOAP::PSGI - wrap a SOAP service as a PSGI app

=head1 SYNOPSIS

  my $app = XML::Compile::SOAP::PSGI->new(
        wsdl_file   => 'wsdl/foo.wsdl',
        impl_object => TestImpl->new,
  );
  $app->to_app;

=head1 METHODS

=cut

use Plack::Request;
use Plack::Util::Accessor qw/ wsdl_file impl_object /;

use File::Slurp qw/ read_file /;

use XML::Compile::SOAP11;
use XML::Compile::WSDL11;

use base qw/ Plack::Component XML::Compile::SOAP::HTTPDaemon /;

=head2 new( ... )

Constructor. Expects hash parameters:

 * wsdl_file - path to the WSDL file to use
 * impl_object - instantiated object with SOAP methods

=cut

sub new {
        my $class = shift;
        my $self = $class->SUPER::new(@_);

        my $text = read_file($self->wsdl_file);
        my $wsdl = XML::Compile::WSDL11->new($text);
        
        my $callbacks = {};
        for my $op ($wsdl->operations) {
                my $callback = $self->_soap_callback($op->name);
                $callbacks->{$op->name} = $callback;
        }
        $self->operationsFromWSDL($wsdl, callbacks => $callbacks);

        # enable dispatch based on Body
        $self->{accept_slow_select} = 1;
        
        return $self;
}

=head2 call($self, $env)

PSGI entry point

=cut

sub call {
        my ($self, $env) = @_;
        
        my $request = Plack::Request->new($env);
        
        # serve wsdl?
        if ($request->method eq 'GET' && $request->request_uri =~ /\?wsdl$/) {
                return $self->_serve_wsdl;
        }

        # run SOAP req on POST
        if ($request->method eq 'POST') {
                my $parser = XML::LibXML->new;
                my $doc = $parser->load_xml( IO => $request->body );

                my $action = $self->actionFromHeader($request);
                my ($status, $huh, $response) 
                     = $self->process($doc, $request, $action);

                return [$status, [], [$response->toString]];
        }

        # else html service desc TODO
        [404, [], []];
}

sub _soap_callback {
        my ($self, $method) = @_;

        return sub {
                my ($soap, $doc) = @_;
                my $response = $self->impl_object->$method($soap, $doc);
                return $response;
        };
}

sub _serve_wsdl {
        my ($self) = @_;
        my $text = read_file($self->wsdl_file);
        return [200, [], [$text]];
}

1;
