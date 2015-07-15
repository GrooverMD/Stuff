#!/usr/bin/env perl

#use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use JSON;
use Exception::Class;
use Win32::Console::Ansi;
use Term::ANSIColor qw(:constants);
use Term::ANSIColor 4.00 qw(RESET :constants256);


  our %opts = (
        h => 0,
        v => 0,
        maxlevel => 30,
        maxnum => 31,
        config => "lacuna.yml",
        dumpfile => "log/all_builds.js",
        station => 0,
        maxadd  => 4, #change for max buildings in the que
        wait    => 60 * 60 * 60,
        sleep  => 1,
        extra  => [],
        noup   => [],
  );

  my $ok = GetOptions(\%opts,
    'h|help',
    'v|verbose',
    'planet=s@',
    'skip=s@',
    'config=s',
    'dumpfile=s',
    'maxadd=i',
    'maxlevel=i',
    'maxnum=i',
    'dry',
    'wait=i',
    'junk' => \$upjunk,
    'glyph' => \$upglyph,
    'space' => \$upspace,
    'city' => \$upcity,
    'lab' => \$uplab,
    'nostandard' => \$upnostandard,
		'storage' => \$upstorage,
		'command' => \$upcommand,
		'sslab' => \$upsslab,
		'resources' => \$upresources,
		'saws' => \$upsaws,
		'ships' => \$upships,
		'speed' => \$upspeed,
    'match=s@',
    'noup=s@',
    'extra=s@',
    'sleep=i',
		'maxhours=i',
  );
	
	my $maxhours = $opts{maxhours};
		
	#warn "\n";
	
	
	cprint( "\nUpgrading", MAGENTA, 1 );
	cprint( " - ", WHITE, 1 );
	
	cprint( "All Junk sculptures. \n\n", BLACK, 1 ) if $upjunk;
	cprint( "Lost City of Tyleon buildings. \n\n", BLACK, 1 ) if $upcity;
	cprint( "Glyph Buildings. \n\n", BLACK, 1 ) if $upglyph;
  cprint( "space. \n\n",  BLACK, 1 ) if $upspace;
  cprint( "All laboratories. \n\n",  BLACK, 1 ) if $uplab;
  cprint( "All non standard buildings. \n\n",  BLACK, 1 ) if $upnostandard;
	cprint( "All storage buildings. \n\n",  BLACK, 1 ) if $upstorage;
	cprint( "All command buildings. \n\n", BLACK, 1 ) if $upcommand;
	cprint( "All Space Station buildings. \n\n",  BLACK, 1 ) if $upsslab;
	cprint( "All Resource Buldings. \n\n",  BLACK, 1 ) if $upresources;
	cprint( "All shields against weapons. \n\n",  BLACK, 1 ) if $upsaws;
	cprint( "All Space Ports and Shipyards. \n\n",  BLACK, 1 ) if $upships;
	cprint( "The Oversight Minstry. \n\n",  BLACK, 1 ) if $upspeed;
	
	warn "\n";
	
  usage() if (!$ok or $opts{h});
  
  set_items();
  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "lacuna.yml",
    rpc_sleep => $opts{sleep},
    # debug    => 1,
  );

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);
  open(OUTPUT, ">", $opts{dumpfile}) || die "Could not open $opts{dumpfile} for writing";

  my $status;
  my $empire = $glc->empire->get_status->{empire};
  
	cprint( "Starting RPC: ", WHITE, 1 );
	cprint( $glc->{rpc_count} . "\n\n", BLACK, 1 );

# Get planets
  my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};
  $status->{planets} = \%planets;

  my @plist = planet_list(\%planets, \%opts);

  my $keep_going = 1;
  my $lowestqueuetimer = $opts{wait} - 1;
  my $currentqueuetimer = 0;
  my %build_err;
  do {
    my $pname;
    my @skip_planets;
    for $pname (sort keys %planets) {
      unless (grep { $pname eq $_ } @plist) {
        push @skip_planets, $pname;
        next;
      }
      cprint( "Inspecting $pname\n", MAGENTA, 1 );
      my $planet    = $glc->body(id => $planets{$pname});
      my $result    = $planet->get_buildings;
      my $buildings = $result->{buildings};
      my $station = $result->{status}{body}{type} eq 'space station' ? 1 : 0;
      if ($station) {
        push @skip_planets, $pname;
        next;
      }
# Station and checking for resources needed.
      my ($sarr, $pending) = bstats($buildings, \%build_err, $station);
				if ($pending > 0) 
					{
						$currentqueuetimer = $pending;
					}
				elsif (scalar @$sarr == 0) 
					{
						cprint( "No buildings to upgrade on $pname\n", RED, 1 );
						$currentqueuetimer = $opts{wait} + 1;
						print "\n";
					}
					
      for my $bld (@$sarr) {
        my $ok;
        my $bldstat = "Bad";
        my $reply = "";
        $ok = eval {
          my $type = get_type_from_url($bld->{url});
          my $bldpnt = $glc->building( id => $bld->{id}, type => $type);
          if ($opts{dry}) {
            $reply = "dry run";
            $lowestqueuetimer = $opts{wait} - 1;
          }
          else {
            $reply = "Upgrading to level: " . ++$bld->{level} ;
            $bldstat = $bldpnt->upgrade();
            $currentqueuetimer = $bldstat->{building}->{pending_build}->{seconds_remaining};
          }
        };
        
				cprint( "Level: " . --$bld->{level}, BLACK, 1 );
				cprint( " - ", WHITE, 1 );
				cprint( $bld->{name}, GREEN, 1 );
				cprint( " - ", WHITE, 1 );
				cprint( $reply . "\n\n", MAGENTA, 1 );  
				
				#printf "%7d %10s level:%2d x:%2d y:%2d %s\n", $bld->{id}, $bld->{name}, --$bld->{level}, $bld->{x}, $bld->{y}, $reply;
				
        unless ($ok) {
          cprint( "$@ Error; Placing building on skip list\n", RED, 1 );
          $build_err{$bld->{id}} = $@;
        }
      }
      if ($lowestqueuetimer > $currentqueuetimer ) {
        $lowestqueuetimer = $currentqueuetimer;
        cprint( sec2str($lowestqueuetimer), WHITE, 0 );
        cprint( " new lowest sleep time.\n\n", BLACK, 1 );
      }  
      $status->{"$pname"} = $sarr;
      if ($currentqueuetimer > $opts{wait}) {
        print "Queue of ", sec2str($currentqueuetimer), " is longer than wait period of ", sec2str($opts{wait}), ", taking $pname off of list.\n\n";
        push @skip_planets, $pname;
      }
    }
    cprint( "Done or skipping: \n\n", YELLOW, 1 );
		#print join(" : " . "\n", sort @skip_planets), "\n";
		cprint( join("" . "\n", sort @skip_planets) . "\n", BLACK, 1 );
		print "\n";
		
    for $pname (@skip_planets) {
      delete $planets{$pname};
    }
    if (keys %planets) {
      cprint( "Clearing Queue for ", WHITE, 0 );
			cprint( sec2str($lowestqueuetimer) . ".\n", BLACK, 1 );
			
      sleep $lowestqueuetimer if $lowestqueuetimer > 0;
      $lowestqueuetimer = $opts{wait} - 1;
    }
    else {
      cprint( "Nothing Else to do.\n", RED, 1 );
      $keep_going = 0;
    }
  } while ($keep_going);

 print OUTPUT $json->pretty->canonical->encode($status);
 close(OUTPUT);
 cprint( "Ending RPC: $glc->{rpc_count}\n\n", BLUE, 1 );

exit;

sub planet_list {
  my ($phash, $opts) = @_;

  my @good_planets;
  for my $pname (sort keys %$phash) {
    if ($opts->{skip}) {
      next if (grep { $pname eq $_ } @{$opts->{skip}});
    }
    if ($opts->{planet}) {
      push @good_planets, $pname if (grep { $pname eq $_ } @{$opts->{planet}});
    }
    else {
      push @good_planets, $pname;
    }
  }
  return @good_planets;
}

sub set_items {
  my $sslab = [
		"Space Station Lab (A)",
    "Space Station Lab (B)",
    "Space Station Lab (C)",
    "Space Station Lab (D)",
	];
	
	my $command = [
		"Development Ministry",
		"Oversight Ministry",
		"Planetary Command Center",
	];
	
	my $storage = [
		"Distribution Center",
		"Energy Reserve",
		"Food Reserve",
		"Ore Storage Tanks",
		"Water Storage Tank",
	];
	
	my $unless = [
		"Beach [1]",
		"Beach [10]",
		"Beach [11]",
		"Beach [12]",
		"Beach [13]",
		"Beach [2]",
		"Beach [3]",
		"Beach [4]",
		"Beach [5]",
		"Beach [6]",
		"Beach [7]",
		"Beach [8]",
		"Beach [9]",
		"Crater",
		"Essentia Vein",
		"Fissure",
		"Gas Giant Settlement Platform",
		"Grove of Trees",
		"Lagoon",
		"Lake",
		"Rocky Outcropping",
		"Patch of Sand",
		"Subspace Supply Depot",
		"Supply Pod",
		"The Dillon Forge",
  ];
  
	my $junk = [
    "Great Ball of Junk",
    "Junk Henge Sculpture",
    "Metal Junk Arches",
    "Pyramid Junk Sculpture",
    "Space Junk Park",
  ];
  
	my $glyph = [
		"Algae Pond",
		"Amalgus Meadow",
		"Beeldeban Nest",
		"Black Hole Generator",
		"Citadel of Knope",
		"Crashed Ship Site",
		"Denton Brambles",
		"Geo Thermal Vent",
		"Gratch's Gauntlet",
		"Interdimensional Rift",
		"Kalavian Ruins",
		"Kastern's Keep",
		"Lapis Forest",
		"Library of Jith",
		"Malcud Field",
		"Massad's Henge",
		"Natural Spring",
		"Oracle of Anid",
		"Pantheon of Hagness",
		"Ravine",
		"Temple of the Drajilites",
		"Volcano",
  ];
  
	my $space = [
    "Space Port",
  ];
  
	my $city = [
    "Lost City of Tyleon (A)",
    "Lost City of Tyleon (B)",
    "Lost City of Tyleon (C)",
    "Lost City of Tyleon (D)",
    "Lost City of Tyleon (E)",
    "Lost City of Tyleon (F)",
    "Lost City of Tyleon (G)",
    "Lost City of Tyleon (H)",
    "Lost City of Tyleon (I)",
  ];
  
	my $lab = [
    "Space Station Lab (A)",
    "Space Station Lab (B)",
    "Space Station Lab (C)",
    "Space Station Lab (D)",
    "Gas Giant Lab",
    "Terraforming Lab",
  ];
	
	my $resources = [
		"Algae Cropper",
		"Algae Syrup Bottler",
		"Atmospheric Evaporator",
		"Amalgus Bean Plantation",
		"Apple Orchard",
		"Beeldeban Herder",
		"Bread Bakery",
		"Malcud Burger Packer",
		"Cheese Maker",
		"Denton Root Chip Frier",
		"Apple Cider Bottler",
		"Corn Plantation",
		"Corn Meal Grinder",
		"Dairy Farm",
		"Denton Root Patch",
		"Geo Energy Plant",
		"Hydrocarbon Energy Plant",
		"Lapis Orchard",
		"Malcud Fungus Farm",
		"Mine",
		"Potato Pancake Factory",
		"Potato Patch",
		"Lapis Pie Bakery",
		"Potato Pancake Factory",
		"Beeldeban Protein Shake Factory",
		"Singularity Energy Plant",
		"Water Production Plant",
		"Water Purification Plant",
		"Wheat Farm",
	];
	
	my $saws = [
		"Shield Against Weapons",
	];
	
	my $ships = [
		"Space Port",
		"Shipyard",
	];
	
	my $speed = [
		"Oversight Ministry",
	];
  
	my $standard = [
		"Algae Cropper",
		"Amalgus Meadow",
		"Archaeology Ministry",
		"Atmospheric Evaporator",
		"Amalgus Bean Plantation",
		"Amalgus Bean Soup Cannery",
		"Beeldeban Herder",
		"Bread Bakery",
		"Malcud Burger Packer",
		"Capitol",
		"Cheese Maker",
		"Denton Root Chip Frier",
		"Apple Cider Bottler",
		"Cloaking Lab",
		"Corn Plantation",
		"Corn Meal Grinder",
		"Dairy Farm",
		"Denton Root Patch",
		"Development Ministry",
		"Distribution Center",
		"Embassy",
		"Energy Reserve",
		"Entertainment District",
		"Espionage Ministry",
		"Fission Reactor",
		"Food Reserve",
		"Fusion Reactor",
		"Genetics Lab",
		"Geo Energy Plant",
		"Hydrocarbon Energy Plant",
		"Intel Training",
		"Intelligence Ministry",
		"Lapis Orchard",
		"Luxury Housing",
		"Malcud Fungus Farm",
		"Mayhem Training",
		"Mercenaries Guild",
		"Mine",
		"Mining Ministry",
		"Mission Command",
		"Munitions Lab",
		"Network 19 Affiliate",
		"Observatory",
		"Ore Refinery",
		"Ore Storage Tanks",
		"Oversight Ministry",
		"Potato Pancake Factory",
		"Park",
		"Lapis Pie Bakery",
		"Pilot Training Facility",
		"Planetary Command Center",
		"Politics Training",
		"Potato Pancake Factory",
		"Propulsion System Factory",
		"Shield Against Weapons",
		"Security Ministry",
		"Beeldeban Protein Shake Factory",
		"Shipyard",
		"Singularity Energy Plant",
		"Space Port",
		"Amalgus Bean Soup Cannery",
		"Stockpile",
		"Subspace Supply Depot",
		"Algae Syrup Bottler",
		"Theft Training",
		"Theme Park",
		"Trade Ministry",
		"Subspace Transporter",
		"University",
		"Waste Digester",
		"Waste Energy Plant",
		"Waste Exchanger",
		"Waste Recycling Center",
		"Waste Sequestration Well",
		"Waste Treatment Center",
		"Water Production Plant",
		"Water Purification Plant",
		"Water Reclamation Facility",
		"Water Storage Tank",
		"Wheat Farm",
  ];
		
		if ($upcity) 
			{
				push @{$opts{match}}, @$city;
			}
		else 
			{
				push @{$opts{noup}}, @$city;
			}
				
		if ($upspeed) 
			{
				push @{$opts{match}}, @$speed;
			}
	
			
		if ($upships) 
			{
				push @{$opts{match}}, @$ships;
			}
			
			
		if ($upsaws) 
			{
				push @{$opts{match}}, @$saws;
			}
				
		if ($upresources) 
			{
				push @{$opts{match}}, @$resources;
			}
			
		if ($upsslab) 
			{
				push @{$opts{match}}, @$sslab;
			}
		else 
			{
				push @{$opts{noup}}, @$sslab;
			}
			
		if ($upcommand) 
			{
				push @{$opts{match}}, @$command;
			}
			
		if ($upstorage) 
			{
				push @{$opts{match}}, @$storage;
			}
				
		if ($opts{nostandard}) 
			{
				push @{$opts{noup}}, @$standard;
			}
  
		if ($upjunk) 
			{
				push @{$opts{match}}, @$junk;
			}
		else 
			{
				push @{$opts{noup}}, @$junk;
			}
		  
		if ($upglyph) 
			{
				push @{$opts{match}}, @$glyph;
			}
		else 
			{
				push @{$opts{noup}}, @$glyph;
			}
						
		if ($opts{space}) 
			{
				push @{$opts{extra}}, @$space;
			}
		else 
			{
				push @{$opts{noup}}, @$space;
			}
					
		if ($opts{lab}) 
			{
				push @{$opts{extra}}, @$lab;
			}
		else 
			{
				push @{$opts{noup}}, @$lab;
			}
			
  push @{$opts{noup}}, @$unless;

#  print "Extra: ",join(", ", @{$opts{extra}}), "\n";
#  print "Skip : ",join(", ", @{$opts{noup}}), "\n";
}

sub bstats {
  my ($bhash, $berr, $station) = @_;

  my $bcnt = 0;
  my $dlevel = $station ? 121 : 0;
  my @sarr;
  my $pending = 0;
  for my $bid (keys %$bhash) {
    if ($bhash->{$bid}->{name} eq "Development Ministry") {
      $dlevel = $bhash->{$bid}->{level};
    }
    $dlevel = $opts{maxnum} if ( $opts{maxnum} < $dlevel );
    if ( defined($bhash->{$bid}->{pending_build})) {
      $bcnt++;
      $pending = $bhash->{$bid}->{pending_build}->{seconds_remaining}
          if ($bhash->{$bid}->{pending_build}->{seconds_remaining} > $pending);
    }
    else {
      my $doit = check_type($bhash->{$bid});
      $doit = 0 if ($berr->{$bid});
      if ($doit) {
#        print "Doing $bhash->{$bid}->{name}\n";
        my $ref = $bhash->{$bid};
        $ref->{id} = $bid;
        push @sarr, $ref if ($ref->{level} < $opts{maxlevel} && $ref->{efficiency} == 100);
      }
      else {
#        print "Skip  $bhash->{$bid}->{name}\n";
      }
    }
  }
  @sarr = sort { $a->{level} <=> $b->{level} ||
                 $a->{x} <=> $b->{x} ||
                 $a->{y} <=> $b->{y} } @sarr;
  if (scalar @sarr > ($dlevel + 1 - $bcnt)) {
    splice @sarr, ($dlevel + 1 - $bcnt);
  }
  if (scalar @sarr > $opts{maxadd}) {
    splice @sarr, $opts{maxadd};
  }
  return (\@sarr, $pending);
}

sub check_type {
  my ($bld) = @_;
  
  ColorPrint(BLUE, "Checking $bld->{name} - ") if ($opts{v});
  if ($opts{match}) {
    if (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{match}}) {
      print "Match\n" if ($opts{v});
      return 1;
    }
    else {
      print "No match\n" if ($opts{v});
      return 0;
    }
  }
  if ($opts{extra} and (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{extra}})) {
    print "Extra\n" if ($opts{v});
    return 1;
  }
  if ($opts{noup} and (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{noup}})) {
    print "Skipping\n" if ($opts{v});
    return 0;
  }
  print "Default\n" if ($opts{v});
  return 1;
}

sub sec2str {
  my ($sec) = @_;

  my $day = int($sec/(24 * 60 * 60));
  $sec -= $day * 24 * 60 * 60;
  my $hrs = int( $sec/(60*60));
  $sec -= $hrs * 60 * 60;
  my $min = int( $sec/60);
  $sec -= $min * 60;
  return sprintf "%04d:%02d:%02d:%02d", $day, $hrs, $min, $sec;
}

sub get_type_from_url {
  my ($url) = @_;

  my $type;
  eval {
    $type = Games::Lacuna::Client::Buildings::type_from_url($url);
  };
  if ($@) {
    print "Failed to get building type from URL '$url': $@";
    return 0;
  }
  return 0 if not defined $type;
  return $type;
}

sub usage {
    diag(<<END);
Usage: $0 [options]

This program upgrades planets on your planet. Faster than clicking each port.
It will upgrade in order of level up to maxlevel.

Options:
  --help             - This info.
  --verbose          - Print out more information
  --config FILE      - Specify a GLC config file, normally lacuna.yml
  --planet NAME      - Specify planet
  --skip  PLANET     - Do not process this planet
  --dumpfile FILE    - data dump for all the info we don't print
  --maxlevel INT     - do not upgrade if this level has been achieved
  --maxnum INT       - Use this if lower than dev ministry level
  --maxadd INT       - Add at most INT buildings to the queue per pass
  --wait   INT       - Max number of seconds to wait to repeat loop
  --sleep  INT       - Pause between RPC calls. Default 1
  --junk             - Upgrade Junk Buildings
  --glyph            - Upgrade Glyph Buildings
  --space            - Upgrade spaceports
  --city             - Upgrade LCOT
  --lab              - Upgrade labs
  --nostandard       - Do not upgrade anything that is not in the other catagories
  --match STRING     - Only upgrade matching building names
  --noup  STRING     - Skip building names (multiple allowed)
  --extra STRING     - Add matching names to usual list to upgrade
  --dry              - Do not actually upgrade
  );
END
  my $bld_names = bld_names();
  print "\nBuilding Names: ",join(", ", sort @$bld_names ),"\n";
  exit 1;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub output {
    return if $opts{q};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}

sub bld_names {
  my $bld_names = [
			"Algae Cropper",
			"Algae Pond",
			"Amalgus Meadow",
			"Apple Orchard",
			"Archaeology Ministry",
			"Art Museum",
			"Atmospheric Evaporator",
			"Beach [1]",
			"Beach [10]",
			"Beach [11]",
			"Beach [12]",
			"Beach [13]",
			"Beach [2]",
			"Beach [3]",
			"Beach [4]",
			"Beach [5]",
			"Beach [6]",
			"Beach [7]",
			"Beach [8]",
			"Beach [9]",
			"Amalgus Bean Plantation",
			"Beeldeban Herder",
			"Beeldeban Nest",
			"Black Hole Generator",
			"Bread Bakery",
			"Malcud Burger Packer",
			"Capitol",
			"Cheese Maker",
			"Denton Root Chip Frier",
			"Apple Cider Bottler",
			"Citadel of Knope",
			"Cloaking Lab",
			"Corn Plantation",
			"Corn Meal Grinder",
			"Crashed Ship Site",
			"Crater",
			"Culinary Institute",
			"Dairy Farm",
			"Denton Root Patch",
			"Denton Brambles",
			"Deployed Bleeder",
			"Development Ministry",
			"Distribution Center",
			"Embassy",
			"Energy Reserve",
			"Entertainment District",
			"Espionage Ministry",
			"Essentia Vein",
			"Fission Reactor",
			"Fissure",
			"Food Reserve",
			"Fusion Reactor",
			"Gas Giant Lab",
			"Gas Giant Settlement Platform",
			"Genetics Lab",
			"Geo Energy Plant",
			"Geo Thermal Vent",
			"Gratch's Gauntlet",
			"Great Ball of Junk",
			"Grove of Trees",
			"Halls of Vrbansk",
			"Hydrocarbon Energy Plant",
			"Interstellar Broadcast System",
			"Intel Training",
			"Intelligence Ministry",
			"Interdimensional Rift",
			"Junk Henge Sculpture",
			"Kalavian Ruins",
			"Kastern's Keep",
			"Lost City of Tyleon (A)",
			"Lost City of Tyleon (B)",
			"Lost City of Tyleon (C)",
			"Lost City of Tyleon (D)",
			"Lost City of Tyleon (E)",
			"Lost City of Tyleon (F)",
			"Lost City of Tyleon (G)",
			"Lost City of Tyleon (H)",
			"Lost City of Tyleon (I)",
			"Lagoon",
			"Lake",
			"Lapis Orchard",
			"Lapis Forest",
			"Library of Jith",
			"Luxury Housing",
			"Malcud Fungus Farm",
			"Malcud Field",
			"Massad's Henge",
			"Mayhem Training",
			"Mercenaries Guild",
			"Metal Junk Arches",
			"Mine",
			"Mining Ministry",
			"Mission Command",
			"Munitions Lab",
			"Natural Spring",
			"Network 19 Affiliate",
			"Observatory",
			"Opera House",
			"Oracle of Anid",
			"Ore Refinery",
			"Ore Storage Tanks",
			"Oversight Ministry",
			"Potato Pancake Factory",
			"Pantheon of Hagness",
			"Park",
			"Parliament",
			"Lapis Pie Bakery",
			"Pilot Training Facility",
			"Planetary Command Center",
			"Police Station",
			"Politics Training",
			"Potato Pancake Factory",
			"Propulsion System Factory",
			"Pyramid Junk Sculpture",
			"Ravine",
			"Rocky Outcropping",
			"Shield Against Weapons",
			"Space Station Lab (A)",
			"Space Station Lab (B)",
			"Space Station Lab (C)",
			"Space Station Lab (D)",
			"Space Port",
			"Patch of Sand",
			"Security Ministry",
			"Beeldeban Protein Shake Factory",
			"Shipyard",
			"Singularity Energy Plant",
			"Amalgus Bean Soup Cannery",
			"Space Junk Park",
			"Station Command Center",
			"Stockpile",
			"Subspace Supply Depot",
			"Supply Pod",
			"Algae Syrup Bottler",
			"Temple of the Drajilites",
			"Terraforming Lab",
			"Terraforming Platform",
			"The Dillon Forge",
			"Theft Training",
			"Theme Park",
			"Trade Ministry",
			"Subspace Transporter",
			"University",
			"Volcano",
			"Warehouse",
			"Waste Digester",
			"Waste Energy Plant",
			"Waste Exchanger",
			"Waste Recycling Center",
			"Waste Sequestration Well",
			"Waste Treatment Center",
			"Water Production Plant",
			"Water Purification Plant",
			"Water Reclamation Facility",
			"Water Storage Tank",
			"Wheat Farm",
		];
  return $bld_names;
}

sub ColorPrint
	{
		my ($color, $msg) = @_;
		print STDERR $color, ON_BLACK, $msg, RESET;
	}
	
sub cprint
	{
		my ( $msg, $color, $bold ) = @_;
		
			if ( $bold )
				{
					print BOLD, $color, $msg, RESET;
				}
			else
				{
					print $color, $msg, RESET;
				}
	}
