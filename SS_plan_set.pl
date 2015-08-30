
# THINGS TO DO
# 1. Learn perl
# 2. Learn perl
# 3. Learn perl
# etc.

#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long   qw( GetOptions );
use List::Util     qw( first );
use Number::Format qw( format_number );
use Config;
	
	if ( $Config{osname} eq "MSWin32" )
		{
			require Win32::Console::Ansi; #adds console colour if a windows box
		}

use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client ();
use Games::Lacuna::Client::PrettyPrint qw( ptime );

use Term::ANSIColor qw(:constants); 

use feature qw(switch say);

my $BLK = BLACK;
my $BLU = BLUE;
my $CYN = CYAN;
my $GRN = GREEN;
my $MAG = MAGENTA;
my $RED = RED;
my $WHT = WHITE;
my $YEL = YELLOW;

my %opts;

my $lab_names;
my @timestats;
my $tolevel;
my $waittime;
my $planet;

no warnings 'experimental::smartmatch'; # suppress experimental warnings. This is for given/when construct in cprint!

GetOptions(
    \%opts,
		'planet=s',
		'level=i',
		'tolevel=i',
		'nwp',  
		'subsidize', #will chew up your E's very quickly if used and your planet might run out of resources before plan sets are complete - USE WITH CAUTION NO REFUNDS ARE GIVEN OR WARRANTIES IMPLIED -
		'help|h',
	);

#-------------------copied this code from ss_lab.pl-----------------------------------
#will make a sub for this when I can and module TLE::logon()!

usage() if $opts{help};
usage() if !exists $opts{planet};
usage() if ( $opts{level} && !$opts{planet} ) || ( $opts{planet} && !$opts{level} );

my $cfg_file = shift(@ARGV) || 'lacuna.yml';

unless ( $cfg_file and -e $cfg_file ) 
	{
		$cfg_file = eval
			{
				require File::HomeDir;
				require File::Spec;
				my $dist = File::HomeDir->my_dist_config( 'Games-Lacuna-Client' );
				File::Spec->catfile( $dist, 'login.yml' ) 
					if $dist;
			};
		
		unless ( $cfg_file and -e $cfg_file ) 
			{
				die "Did not provide a config file";
			}
	}

my $client = Games::Lacuna::Client->new(
	cfg_file => $cfg_file,
	# debug    => 1,
);

my $status;	

my $empire = $client->empire->get_status->{empire};

# reverse hash, to key by name instead of id
my %planets = reverse %{ $empire->{planets} };

# Load planet data
my $body   = $client->body( id => $planets{ $opts{planet} } );
my $result = $body->get_buildings;

my $buildings = $result->{buildings};

# Find the SSLab
my $ssl_id = first { $buildings->{$_}->{url} eq '/ssla' } keys %$buildings;

die "No SS Lab on this planet\n" if !$ssl_id;

my $sslab = $client->building( id => $ssl_id, type => 'SSLA' );
	
print "\n";

#------------------------ my code -------------------------------------

if ( !exists $opts{tolevel} ) #set --tolevel to --level if --tolevel is not used, builds only one level of plans.
	{
		$tolevel = $opts{level};
	}
else
	{
		$tolevel = $opts{tolevel};
			
			if( $opts{tolevel} < $opts{level} )
				{
					die "Plan tolevel lower then the level!"; #can remove this as taking this out will build downto
				}
	}

get_build_times();

#----------------------------------------------------------------------	
#------------ main plan building code ---------------------------------
#----------------------------------------------------------------------

cprint( "Starting RPC: $client->{rpc_count}", $CYN, 1, 2 );

	foreach my $i ( $opts{level}..$tolevel )
		{
			get_lab_names( $i );
			cprint( "Making Lab Plan Set: On planet $opts{planet}", $WHT, 0, 2 );		
							
				foreach my $lab_names (@$lab_names)
					{		
						sleep make_plan( $lab_names, $i );
					}
					
			cprint( "Level: " . $i . " Space Station plans complete on " . $opts{planet}, $YEL, 1, 2 );
		}
	
	if( $opts{level} == $tolevel )
		{
			cprint ( "Finished building SS lab plans level $opts{level}!", $GRN, 1 ,2 );
		}
	else
		{
			cprint ( "Finished building SS lab plans level $opts{level} to level $tolevel!", $GRN, 1 ,2 );	
		}
	
	cprint( "Ending RPC: $client->{rpc_count}", $CYN, 1, 1 );
	
exit;

#------------ Subs ------------------------------------------------------
#------------ Gets build times for each SS plan level -------------------
#------------ Used some code from SS_lab.pl -----------------------------
#probably a better way to do this will have to find out!

sub get_build_times
	{
		my $loop = 1;
		
		my $status = $sslab->view->{make_plan};
		my $costs = $status->{level_costs};
		
			for my $type ( @$costs ) 
				{
					$type->{time} = ptime( $type->{time} );
					$timestats[$loop] = $type->{time}; #the magic code as I don't know how this works, but it does.			
					$loop++;
				}
		
	}

#------------ make_plan ---------------------------------------------------
#------------ makes a plan and returns the wait time for the plan ---------
#------------ if subsidized returns 0 wait time. --------------------------
#------------ exits if plan is already being made -------------------------

sub make_plan 
	{
    my ( $plantype, $level ) = @_;		
		
		my $status = $sslab->view->{make_plan};
			
			if ( my $making = $status->{making} ) 
			{
        cprint( "Already making SS Lab plan type $making. Please wait for plan to finish building!", $YEL, 1, 2 );
				exit;
			}
		
		$status = $sslab->make_plan( $plantype, $level );
				
		cprint( "Making: Level " . $level . " "  . ProperName( $plantype ) . " on ". $opts{planet} , $MAG, 1, 1 );
		
			if( exists $opts{subsidize} )
				{
					my $status = $sslab->subsidize_plan;
					$waittime = "0";
				}
			else
				{
					$waittime = $timestats[$level];
				}
		
		cprint( "Wait time: " . $waittime, $GRN, 1, 2 );
		
		return str2sec( $waittime );
	}

#------------ Prints Color --------------------------------------------
#------------ took out win32 only -------------------------------------
#------------ should work on linux, osx -------------------------------
#------------ will put this in a module when I get the time -----------

sub cprint
	{
		my ( $msg, $color, $bold, $newline ) = @_;
		my $newmsg;
			
			given ($newline)
				{
					when (0)
						{
							$newmsg = $msg . " "; #No new line but space in between. Can print on same line
						}
						
					when (1)
						{
							$newmsg = $msg . "\n"; #Next text printed on a new line
						}
						
					when (2)
						{
							$newmsg = $msg . "\n\n"; #Add empty line between text
						}
				}
			
			if ( $bold )
				{
					print BOLD, $color, $newmsg, RESET;
				}
			else
				{
					print $color, $newmsg, RESET;
				}
	}
	
#------------ Returns Proper Plan Names for printing ---------------------------------------

sub ProperName
	{
		my ( $name ) = @_;
				
			if( $name eq "art" ) { $name = "Art Museum"; }
				
			if( $name eq "opera" ) { $name = "Opera House"; }
				
			if( $name eq "parliament" ) { $name = "Parliament"; }
			
			if( $name eq "ibs" ) { $name = "Interstellar Broadcast System"; }
				
			if( $name eq "command" ) { $name = "Station Command Centre"; }
				
			if( $name eq "warehouse" ) { $name = "Warehouse"; }
				
			if( $name eq "food" ) { $name = "Culinary Institute"; }
				
			if( $name eq "policestation" ) { $name = "Police Station"; }
				
		return $name;
	}

#------------ Returns Lab Plan Build Names depending on plan levels ------------
#------------ can change this @ later date works for now -----------------------
	
sub get_lab_names 
	{
		my ( $level ) = @_;
		
		if( $level == 1 ) #special case for level 1 SS
			{
				goto LEVEL1;
			}
			
		if( exists $opts{nwp} )
			{
				$lab_names = [
				"art", 
				"food", 
				"ibs", 
				"opera", 
				"parliament",
				"policestation", 
				"command",
				];
				
				goto FINISH;
			}
		else
			{
				$lab_names = [
				"art", 
				"food", 
				"ibs", 
				"opera", 
				"parliament",
				"policestation", 
				"command", 
				"warehouse",
				];
				
				goto FINISH;
			}

LEVEL1:
		
		if( exists $opts{nwp} )
			{
				$lab_names = [
				"art", 
				"food", 
				"ibs", 
				"opera", 
				"policestation", 
				];
			}
		else
			{
				$lab_names = [
				"art",
				"food",
				"ibs",
				"opera",
				"policestation",
				"warehouse",
				];
			}
		
		FINISH:
		
		return $lab_names;
	}

#------------ Seconds to string from upgrade_al.pl --------------------------------

sub sec2str 
	{
		my ($sec) = @_;

		my $day = int($sec/(24 * 60 * 60));
		$sec -= $day * 24 * 60 * 60;
  
		my $hrs = int( $sec/(60*60));
		$sec -= $hrs * 60 * 60;
		
		my $min = int( $sec/60);
		$sec -= $min * 60;
		
		return sprintf "%02d:%02d:%02d:%02d", $day, $hrs, $min, $sec;
	}

#------------ Time string to seconds -----------------------------------------------
#------------ time string format 00:00:00:00 ---------------------------------------
#------------ probably a better way to do this but this works for now --------------

sub str2sec #returns the int( seconds ) needed for the sleep part of make_plan
	{
		my ( $time ) = @_;
			
			if( length $time == 1 ) #need these for the lacuna client plan build time return strings as they return different lengths. Keeps the format consistent!
				{
					$time = "00:00:00:0" . $time;
				}
			
			if( length $time == 2 ) 
				{
					$time = "00:00:00:" . $time;
				}
				
			if( length $time == 4 ) 
				{
					$time = "00:00:0" . $time;
				}
				
			if( length $time == 5 )
				{
					$time = "00:00:" . $time;
				}
				
			if( length $time == 7 )
				{
					$time = "00:0" . $time;
				}
				
			if( length $time == 8 )
				{
					$time = "00:" . $time;
				}
				
			if( length $time == 10 )
				{
					$time = "0" . $time;
				}
		
		my $days = substr $time, 0, 2;
		my $hours = substr $time, 3, 2;
		my $min = substr $time, 6, 2;
		my $sec = substr $time, 9, 2;
		
		return ( int( $days ) * 24 * 60 * 60 ) + ( int( $hours ) * 60 * 60 ) + ( int( $min ) * 60 ) + $sec;
	}
	
#------------ Usage Sub -----------------------------------------------
	
sub usage 
	{
		print "\n";
			if( !exists $opts{planet} )
				{
					cprint( "SS Plan Set error: Planet name required!", $RED, 1, 2 );
				}
			if( !exists $opts{level} )
				{
					cprint( "SS Plan Set error: Level required!", $RED, 1, 2 );
				}
					
		cprint( "Usage: SS_plan_set.pl --planet NAME --level LEVEL", $GRN, 1, 2 );
		cprint( "	--planet    REQUIRED", $MAG, 1, 1 );
		cprint( "	--level     REQUIRED", $MAG, 1, 1 );
		cprint( "	--tolevel   BUILD TO LEVEL (optional)", $MAG, 1, 1 );	
		cprint( "	--nwp       NO WAREHOUSE PLAN (optional)", $MAG, 1, 1 );
		cprint( "	--subsidize YOU CAN USE YOUR E (optional)", $MAG, 1, 1 );
		cprint( "	--help", $MAG, 1, 2 );
		
		cprint( "CONFIG_FILE defaults to 'lacuna.yml'", $WHT, 0, 2 );
		
			if ( !exists $opts{planet} )
				{
					$planet = "your planet";
				}
			else
				{
					$planet = $opts{planet};
				}
					
		cprint( "--planet NAME is required, you need somewhere to build the plan set!", $RED, 1, 1 );
		cprint( "--level LEVEL is required, it will make one set of plans at that level!", $RED, 1, 2 );
		cprint( "If --tolevel is provided, it will make complete plan sets from LEVEL to TOLEVEL e.g. --LEVEL 1 --TOLEVEL 4.", $WHT, 0, 1 );
		cprint( "If --nwp is provided, it will not make a warehouse plan @ the level specified otherwise the script will build a warehouse to each level.", $WHT, 0, 2 );
		cprint( "If --subsidize is also provided, the plan set build will be E-subsidized.", $WHT, 0, 2 );
		cprint( "This option will chew your E's very quickly, if multiple build levels are used, and $planet might run out of resources before the plan sets are complete! You might end up off your planet! :):", $RED, 1, 1 ); 
		cprint( "USE WITH CAUTION AS NO REFUNDS ARE GIVEN OR WARRANTIES IMPLIED FOR THE USE OF THIS SOFTWARE. Check your planet stats before use.", $RED, 1, 2 );
		cprint( "If --help is used, you get the same output as what you can see. It's a bit of a useless option. :)", $WHT, 0, 1 );
		
		exit;
	}