#!/usr/bin/env perl

use strict;
use warnings;

use inc::Module::Install 0.91;
use Module::Install::AuthorRequires;
use Module::Install::AuthorTests;
use Module::Install::ReadmeFromPod;

name 'XML-Compile-SOAP-PSGI';
all_from 'lib/XML/Compile/SOAP/PSGI.pm';

requires 'Plack';
requires 'Template::Tiny';
requires 'XML::Compile::SOAP';
requires 'HTTP::Router::Declare';

author_requires 'Test::NoTabs';
author_requires 'Test::Pod' => '1.14';
author_requires 'Test::Pod::Coverage' => '1.04';

test_requires 'Test::More' => '0.88';

resources
     license     => "http://dev.perl.org/licenses",
     repository  => "http://github.com/chrisa/perl-XMLCompileSOAP-PSGI";

author_tests 't/author';

WriteAll;
