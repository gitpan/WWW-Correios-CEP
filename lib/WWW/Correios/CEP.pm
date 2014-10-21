package WWW::Correios::CEP;

use 5.010001;
use strict;
use warnings;

use LWP::UserAgent;
use HTML::TreeBuilder::XPath ;
use Encode;
use utf8;

our $VERSION = '0.01';


#-------------------------------------------------------------------------------
# Seta configuracao DEFAULT
#-------------------------------------------------------------------------------
sub new {
	my $class = shift();
	my $params = shift();

	my $this  = {
		_tests => [
			{ street => 'Rua Realidade dos Nordestinos', neighborhood => 'Cidade Nova Heliópolis', location => 'São Paulo'     , uf => 'SP', cep => '04236-000' , status => ''},
			{ street => 'Rua Rio Piracicaba'           , neighborhood => 'I.A.P.I.'              , location => 'Osasco'        , uf => 'SP', cep => '06236-040' , status => ''},
			{ street => 'Rua Hugo Baldessarini'        , neighborhood => 'Vista Alegre'          , location => 'Rio de Janeiro', uf => 'RJ', cep => '21236-040' , status => ''},
			{ street => 'Avenida Urucará'              , neighborhood => 'Cachoeirinha'          , location => 'Manaus'        , uf => 'AM', cep => '69065-180' , status => ''}
		],
		_require_tests => 1,
		_tests_status  => undef,
		_user_agent    => 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)',

		_lwp_ua        => undef,

		_post_url      => 'http://www.buscacep.correios.com.br/servicos/dnec/consultaLogradouroAction.do',
		_post_content  => 'StartRow=1&EndRow=10&TipoConsulta=relaxation&Metodo=listaLogradouro&relaxation=',
		
		_pass_test     => 0
	};
	$this->{_require_tests} = $params->{require_tests} if (defined $params->{require_tests});
	$this->{_tests}         = $params->{with_tests}    if (defined $params->{with_tests});
	$this->{_user_agent}    = $params->{user_agent}    if (defined $params->{user_agent});

	$this->{_post_url}      = $params->{_post_url}     if (defined $params->{post_url});
	$this->{_post_content}  = $params->{_post_content} if (defined $params->{post_content});

	bless($this, $class);
	return $this;
}

sub tests {
	my ($this) = @_;

	my $is_ok = 1;
	foreach my $test (@{$this->{_tests}}){
		my $result = $this->_extractAddress($test->{cep});

		my $ok = 1;
		foreach (keys %$result){
			$ok = $result->{$_} eq $test->{$_};
			last unless $ok;
		}
		
		push(@{$this->{_tests_status}}, $result);

		$is_ok = $ok ? $is_ok : 0;
	}

	$this->{_pass_test} = $is_ok;
	return $is_ok;
}

sub find {
	my ($this, $cep) = @_;
	
	$this->tests() if ($this->{_require_tests} && !defined $this->{_tests_status});

	die("Tests FAIL") if (!$this->{_pass_test} && $this->{_require_tests});
	
	return $this->_extractAddress($cep);
}

sub _extractAddress {
	my ($this, $cep) = @_;

	my $result = {};

	$cep =~ s/[^\d]//go;
	$cep = sprintf('%08d', $cep);
	
	if ($cep =~ /^00/o || $cep =~ /(\d)\1{7}/){
		$result->{status} = "Error: Invalid CEP number ($cep)";
	}else{
	
		if(!defined $this->{_lwp_ua}){
			my $ua = LWP::UserAgent->new;
			$ua->agent($this->{_user_agent});
			$this->{_lwp_ua} = $ua;
		}
		my $ua = $this->{_lwp_ua};

		my $req = HTTP::Request->new(POST => $this->{_post_url});
		$req->content_type('application/x-www-form-urlencoded');
		$req->content($this->{_post_content} . $cep);

		# Pass request to the user agent and get a response back
		my $res = $ua->request($req);

		# Check the outcome of the response
		if ($res->is_success) {

			$this->_parseHTML($result, $res->content);
			
			# $result->{status} = $res->content;
		}
		else {
			$result->{status} = "Error: " . $res->status_line;
		}

	}
	
	return $result;
}

sub _parseHTML {
	my ($this, $address, $html) = @_; 

	# WOOOW, $html IS NOT HTML, ITS A INSANE TEXT
	# pqp, isso não é HTML nem aqui nem na china!	

	# POG MODE=ON
	my $serach = quotemeta("<?xml version = '1.0' encoding = 'ISO-8859-1'?>");

	$html =~ s/\n/ /g;

	my ($string) = $html =~ m/$serach(.+\d{5}\-\d{3}\<\/td\>\s*\<\/tr\>\s*<\/table\>)/iom;

	# POG MODE = OFF

	if (!$string){
		$address->{status} = 'Error: pattern not found.';

	}else{

		my $tree = HTML::TreeBuilder::XPath->new;

		$string =  decode("iso-8859-1", $string);
		$tree->parse_content( "<html><body>$string</body></html>" ); # ON AND OFF POG MODE

		my $p = $tree->findnodes( '/html/body/table' )->[0];
	
		$address->{street}       = $p->findvalue('//tr[1]/td[1]');
		$address->{neighborhood} = $p->findvalue('//tr[1]/td[2]');
		$address->{location}     = $p->findvalue('//tr[1]/td[3]');
		$address->{uf}           = $p->findvalue('//tr[1]/td[4]');
		$address->{cep}          = $p->findvalue('//tr[1]/td[5]');
	
		if ($address->{cep}){
			$address->{status}       = '';
		}else{
			$address->{status}       = 'something is wrong..';
		}
	}


	return $address;
}

sub setTests {
	die("Tests must be an array ref") unless ref $_[1] eq 'ARRAY' && ref $_[1][0] eq 'HASH';
	$_[0]->{_tests} = $_[1];
}

sub getTests() {
	shift()->{_tests};
}

sub dump_tests {
	my ($this) = @_;

	print("No tests found!") unless defined $this->{_tests_status};

	foreach (@{$this->{_tests_status}}){
		if ($_->{error}){
			print "$_->{cep}: ERROR $_->{error} - street: $_->{street}, neighborhood: $_->{neighborhood}, location: $_->{location}, uf: $_->{uf}\n" ;
		}else{
			print "$_->{cep}: $_->{street}, $_->{neighborhood} - $_->{location} - $_->{uf}\n"
		}
	}
}

1;
__END__
=encoding utf8

=head1 NAME

WWW::Correios::CEP - Perl extension for extract address from CEP (zip code) number

=head1 SYNOPSIS

	use WWW::Correios::CEP;

	my $cepper = new WWW::Correios::CEP();

	my $address = $cepper->find( $cep );
	# returns hashref like { street => '', neighborhood => '', location => '', uf => 'SP', cep => '', status => '' }


note: if you call "find" before "test" and require_tests is true, tests will be called

=head1 DESCRIPTION

This is the documentation for WWW::Correios::CEP


=head1 METHODS

List of methods

=head2 new WWW::Correios::CEP( { ... } );

Create an instance of WWW::Correios::CEP and configures it
	
Parameters:
	require_tests 
	with_tests
	user_agent
	post_url
	post_content

You can see details on "Full Sample" below


=head2 $cepper->find( $cep )

Recive and CEP and try to get it address returning an hash ref with street, neighborhood, location, uf, cep and status.

=head2 $cepper->tests( )

This method make tests on some address for test if WWW::Correios::CEP still ok,
you may want keep this, these tests use some time, but it depends on your connection speed/correios site speed.

Retuns 1 if all tests are ok, if false, you may want to call dump_tests to see the changes

=head2 $cepper->dump_tests( )

prints on STDOUT results of each test

=head2 $cepper->setTests( $array_ref_of_hash )

You can change tests after new too, but you need to call $cepper->tests() if it already called.

$array_ref_of_hash should be an array ref with hashs like "with_tests" bellow

=head2 $cepper->getTests( )

return current tests array

=head1 INTERNALS

=head2 _parseHTML 

parse "html" of correios sites

=head2 _extractAddress 

internal function called on "tests" and "find" methods


=head1 Full Sample

	my $cepper = new WWW::Correios::CEP(
		# this is default, you can disable it with a explicit false value,
		require_tests => 1,
		# theses tests may fail if the Correios page have changed.
		# Nevertheless, to not break this class when address/cep changes, you can set a your tests here
		with_tests => [
			{ street => 'Rua Realidade dos Nordestinos', neighborhood => 'Cidade Nova Heliópolis', location => 'São Paulo'     , uf => 'SP', cep => '04236000' },
			{ street => 'Rua Rio Piracicaba'           , neighborhood => 'I.A.P.I.'              , location => 'Osasco'        , uf => 'SP', cep => '06236040' },
			{ street => 'Rua Hugo Baldessarini'        , neighborhood => 'Vista Alegre'          , location => 'Rio de Janeiro', uf => 'RJ', cep => '21236040' },
			{ street => 'Avenida Urucará'              , neighborhood => 'Cachoeirinha'          , location => 'Manaus'        , uf => 'AM', cep => '69065180' }
		],
		# if you want to change user agent, that defaults to Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)
		user_agent => 'IECA',

		# if you want to change POST url
		post_url => 'http://www.buscacep.correios.com.br/servicos/dnec/consultaLogradouroAction.do',
		
		# if you want to change post content, remenber that "cep number" will be concat on end of this string
		post_content => 'StartRow=1&EndRow=10&TipoConsulta=relaxation&Metodo=listaLogradouro&relaxation='
	);

	eval{$cepper->tests()};
	if($@){
		# you can use $@ if you want just error message
		$cepper->dump_tests;
	}else{
		my $address = $cepper->find( $cep );

		# returns hashref like { street => '', neighborhood => '', location => '', uf => 'SP', cep => '', status => '' }

	}

=head1 SEE ALSO

WWW::Correios::SRO

=head1 AUTHOR

Renato CRON, E<lt>rentocron@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Renato

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

See http://dev.perl.org/licenses/ for more information.


=cut
