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
use Plack::Response;
use Plack::Util::Accessor qw/ wsdl_file impl_object wsdl /;

use HTTP::Router::Declare;

use XML::LibXML;
use XML::Compile::SOAP11;
use XML::Compile::WSDL11;

use Template::Tiny;
use HTML::Entities;

use base qw/ Plack::Component XML::Compile::SOAP::HTTPDaemon /;

=head2 new( ... )

Constructor. Expects hash parameters:

 * wsdl_file - path to the WSDL file to use
 * impl_object - instantiated object with SOAP methods

=cut

sub new {
        my $class = shift;
        my $self = $class->SUPER::new(@_);

        my $wsdl = XML::Compile::WSDL11->new($self->wsdl_file);
	$self->wsdl($wsdl);

        my $callbacks = {};
        for my $op ($wsdl->operations) {
		my $method = $op->name;
                my $callback = sub {
			my ($soap, $doc) = @_;
			my $response = $self->impl_object->$method($soap, $doc);
			return $response;
		};
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

my $router = router {
	with { controller => 'Self' } => then {

		match '/', { method => 'POST' },
		     to { action => 'soap_method' };

		match '/', { method => 'GET' },
		     to { action => 'index' };

		match '/{op}', { method => 'GET' },
		     to { action => 'form' };

		match '/{op}', { method => 'POST' },
		     to { action => 'http_method' };
	};
};

sub call {
        my ($self, $env) = @_;
        my $req = Plack::Request->new($env);

	my $match = $router->match($req)
	     or return $req->new_response(404)->finalize;

	my $p = $match->params;
	my $action = $self->can($p->{action})
	     or return $req->new_response(405)->finalize;

	my $res = $self->$action($req, $p);
	$res->finalize;
}

sub download_wsdl {
	my ($self, $req, $params) = @_;

	my $file = IO::File->new($self->wsdl_file);
	my $res = Plack::Response->new(200);
	$res->content_type('text/xml');
	$res->body($file);
	return $res;
}

sub soap_method {
	my ($self, $req, $params) = @_;

	my $parser = XML::LibXML->new;

	my $doc;
	eval {
		$doc = $parser->load_xml( IO => $req->body );
	};
	if ($@) {
		return [500, [], [$@]];
	}

	my $action = $self->actionFromHeader($req);
	my ($status, $msg, $soap)
	     = $self->process($doc, $req, $action);

	my $res = Plack::Response->new($status);
	$res->content_type('text/xml');
	$res->body([$soap->toString]);
	return $res;
}

sub index {
	my ($self, $req, $params) = @_;

	if ($req->uri =~ /wsdl$/i) {
		return $self->download_wsdl;
	}

	my $services = {};
	for my $op ($self->wsdl->operations) {
		$services->{$op->serviceName} ||= [];
		push @{$services->{$op->serviceName}}, {
			name => $op->name,
			url  => $req->request_uri . '/' . $op->name,
		};
	}
	my $vars = { services => [] };
	for my $service (keys %$services) {
		push @{$vars->{services}}, {
			name => $service,
			ops  => $services->{$service},
		};
	}

	my $template = Template::Tiny->new;
	my $input = _index_template();
	my $output = '';

	$template->process( \$input, $vars, \$output );
  	
	my $res = Plack::Response->new(200);
	$res->content_type('text/html');
	$res->body($output);
	return $res;
}

sub _index_template {
	return <<EOHTML;
<!DOCTYPE html>
<html>
<head>
<title>SOAP Service</title>
</head>
<body style="font-family: Helvetica">
[% FOREACH service IN services %]
<h1 style="background-color: #4a70bc; color: #fff;">SOAP Service [% service.name %]</h1>
<div>
  <h2>Service Definition</h2>
  <p><a href="?wsdl">WSDL</a></p>
  <h2>Operations</h2>
  [% FOREACH op IN service.ops %]
  <a href="[% op.url %]">[% op.name %]</a>
  [% END %]
</div>
[% END %]
</body>
</html>
EOHTML
}

sub form {
	my ($self, $req, $params) = @_;

	my $op;
	for my $operation ($self->wsdl->operations) {
		if ($params->{op} eq $operation->name) {
			$op = $operation;
			last;
		}
	}

	my $xml;

	# dodgy template section
	my $def = $op->{input_def};
	foreach my $part ( @{$def->{body}{parts} || []} ) {
		my $name = $part->{name};
		my ($kind, $value) = $part->{type} ? (type => $part->{type})
		     : (element => $part->{element});
		my $type = $self->wsdl->prefixed($value) || $value;
		
		$xml .= $self->wsdl->template(XML => $value, skip_header => 1, recurse => 1);
	}

	my $vars = { 
		op => { 
			name => $op->name, 
			template => encode_entities($xml),
		} 
	};

	my $template = Template::Tiny->new;
	my $input = _form_template();
	my $output = '';

	$template->process( \$input, $vars, \$output );
  	
	my $res = Plack::Response->new(200);
	$res->content_type('text/html');
	$res->body($output);
	return $res;
}

sub _form_template {
	return <<EOHTML;
<!DOCTYPE html>
<html>
<head>
<title>SOAP Method</title>
</head>
<body style="font-family: Helvetica">
<h1 style="background-color: #4a70bc; color: #fff;">SOAP Method [% op.name %]</h1>
<pre>
[% op.template %]
</pre>
</body>
</html>
EOHTML
}
