use strict;
use warnings;
use Test::More;

BEGIN {
    plan skip_all => 'backends required' if(!-s 'thruk_local.conf' and !defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'});
    plan tests => 13;
}

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
}

SKIP: {
    skip 'external tests', 1 if defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'};

    use_ok 'Thruk::Controller::woshsh';
};

#################################################
my $pages = [
    { url => '/thruk/cgi-bin/woshsh.cgi', like => [ 'Woshsh', 'test.xls' ] },
];

for my $page (@{$pages}) {
    TestUtils::test_page(%{$page});
}
