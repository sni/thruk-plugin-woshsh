use warnings;
use strict;
use Test::More;

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
}

plan skip_all => 'internal test' if $ENV{'PLACK_TEST_EXTERNALSERVER_URI'};
plan skip_all => 'backends required' if !-s 'thruk_local.conf';
plan tests => 13;

###########################################################
# test modules
unshift @INC, 'plugins/plugins-available/woshsh/lib';
use_ok 'Thruk::Controller::woshsh';

#################################################
my $pages = [
    { url => '/thruk/cgi-bin/woshsh.cgi', like => [ 'Woshsh', 'test.xls' ] },
];

for my $page (@{$pages}) {
    TestUtils::test_page(%{$page});
}
