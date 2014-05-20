#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for access_log.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format test "$uri:$status";

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /combined {
            access_log %%TESTDIR%%/combined.log;
            return 200 OK;

            location /combined/off {
                access_log off;
                return 200 OK;
            }
        }

        location /filtered {
            access_log %%TESTDIR%%/filtered.log test
                       if=$arg_logme;
            return 200 OK;
        }

        location /complex {
            access_log %%TESTDIR%%/complex.log test
                       if=$arg_logme$arg_logmetoo;
            return 200 OK;
        }

        location /compressed {
            access_log %%TESTDIR%%/compressed.log test
                       gzip buffer=1m flush=100ms;
            return 200 OK;
        }

        location /multi {
            access_log %%TESTDIR%%/multi1.log test;
            access_log %%TESTDIR%%/multi2.log test;
            return 200 OK;
        }

        location /varlog {
            access_log %%TESTDIR%%/${arg_logname} test;
            return 200 OK;
        }
    }
}

EOF

$t->try_run('no access_log if')->plan(8);

###############################################################################

http_get('/combined');
http_get('/combined/off');

http_get('/filtered');
http_get('/filtered/empty?logme=');
http_get('/filtered/zero?logme=0');
http_get('/filtered/good?logme=1');
http_get('/filtered/work?logme=yes');

http_get('/complex');
http_get('/complex/one?logme=1');
http_get('/complex/two?logmetoo=1');
http_get('/complex/either1?logme=A&logmetoo=B');
http_get('/complex/either2?logme=A');
http_get('/complex/either3?logmetoo=B');
http_get('/complex/either4?logme=0&logmetoo=0');
http_get('/complex/neither?logme=&logmetoo=');

http_get('/compressed');

http_get('/multi');

http_get('/varlog');
http_get('/varlog?logname=');
http_get('/varlog?logname=0');
http_get('/varlog?logname=filename');


select undef, undef, undef, 0.1;

# verify that "gzip" parameter turns on compression

my $log;

SKIP: {
	eval { require IO::Uncompress::Gunzip; };
	skip("IO::Uncompress::Gunzip not installed", 1) if $@;

	my $gzipped = read_file($t, 'compressed.log');
	IO::Uncompress::Gunzip::gunzip(\$gzipped => \$log);
	is($log, "/compressed:200\n", 'compressed log - flush time');
}

# now verify all other logs

$t->stop();


# verify that by default, 'combined' format is used, 'off' disables logging

$log = read_file($t, 'combined.log');
like($log,
	qr!^\Q127.0.0.1 - - [\E .*
		\Q] "GET /combined HTTP/1.0" 200 2 "-" "-"\E$!x,
	'default log format');

# verify that log filtering works

$log = read_file($t, 'filtered.log');
is($log, "/filtered/good:200\n/filtered/work:200\n", 'log filtering');


# verify "if=" argument works with complex value

my $exp_complex = <<'EOF';
/complex/one:200
/complex/two:200
/complex/either1:200
/complex/either2:200
/complex/either3:200
/complex/either4:200
EOF

$log = read_file($t, 'complex.log');
is($log, $exp_complex, 'if with complex value');


# multiple logs in a same location

$log = read_file($t, 'multi1.log');
is($log, "/multi:200\n", 'multiple logs 1');

# same content in the second log

$log = read_file($t, 'multi2.log');
is($log, "/multi:200\n", 'multiple logs 2');


# test log destinations with variables

$log = read_file($t, '0');
is($log, "/varlog:200\n", 'varlog literal zero name');

$log = read_file($t, 'filename');
is($log, "/varlog:200\n", 'varlog good name');

###############################################################################

sub read_file {
	my ($t, $file) = @_;
	my $path = $t->testdir() . '/' . $file;

	open my $fh, '<', $path or return "$!";
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

###############################################################################