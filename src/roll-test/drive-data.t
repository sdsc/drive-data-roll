#!/usr/bin/perl -w
# drive-data roll installation test.  Usage:
# drive-data.t [nodetype]
#   where nodetype is one of "Compute", "Dbnode", "Frontend" or "Login"
#   if not specified, the test assumes either Compute or Frontend

use Test::More qw(no_plan);

my $appliance = $#ARGV >= 0 ? $ARGV[0] :
                -d '/export/rocks/install' ? 'Frontend' : 'Compute';
my $installedOnAppliancesPattern = '.';
my $isInstalled = -d '/opt/drive-data';
my $output;

my $TESTFILE = 'tmpdrive-data';

if($appliance =~ /$installedOnAppliancesPattern/) {
  ok($isInstalled, 'drive-data installed');
} else {
  ok(! $isInstalled, 'drive-data not installed');
}
SKIP: {

  skip 'drive-data not installed', 4 if ! $isInstalled;
  $output = `module load drive-data; echo 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 | drive-data 2>&1`;
  like($output, qr/That is correct/, 'drive-data runs');
  `/bin/ls /opt/modulefiles/applications/drive-data/[0-9]* 2>&1`;
  ok($? == 0, 'drive-data module installed');
  `/bin/ls /opt/modulefiles/applications/drive-data/.version.[0-9]* 2>&1`;
  ok($? == 0, 'drive-data version module installed');
  ok(-l '/opt/modulefiles/applications/drive-data/.version',
     'drive-data version module link created');

}

`rm -fr $TESTFILE*`;
