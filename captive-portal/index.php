<?php
$game_site = "***REMOVED***";
$site_name = "EPPSA ***REMOVED*** Game";

// The following file is used to keep track of users
$users = "/var/lib/users";

// Attempt to get the client's mac address
$mac = shell_exec("cat /proc/net/arp | grep ".$_SERVER['REMOTE_ADDR']." | awk {'print $4'}");
preg_match('/..:..:..:..:..:../',$mac , $matches);
@$mac = $matches[0];
if (!isset($mac)) { exit; }

if (!isset($_POST['accept'])) {
  ?>
  <h1>Welcome to <?php echo $site_name;?></h1>
  To access the Game you must accept the conditions:<br><br>
  <form method='POST'>
  <input type='hidden' name='accept' value='true'>
  <input type='submit' name='submit' value='Accept Conditions'>
  </form>
  <?php
} else {
    enable_address();
}

// This function enables the device on the system by calling iptables, and also saving the
// details in the users file for next time the firewall is reset

function enable_address() {

    global $accept;
    global $mac;
    global $users;
    global $game_site;

    file_put_contents($users,$_POST['accept']."\t"
        .$_SERVER['REMOTE_ADDR']."\t$mac\t".date("d.m.Y")."\n",FILE_APPEND + LOCK_EX);

    // Add device to the firewall
    exec("iptables -I internet 1 -t mangle -m mac --mac-source $mac -j RETURN");
    // The following line removes connection tracking for the device
    // This clears any previous (incorrect) route info for the redirection
    exec("rmtrack ".$_SERVER['REMOTE_ADDR']);

    sleep(1);
    header("location:http://".$game_site);
    exit;
}

// Function to print page header
function print_header() {

  ?>
  <html>
  <head><title>Welcome to <?php echo $site_name;?></title>
  <META HTTP-EQUIV="CACHE-CONTROL" CONTENT="NO-CACHE">
  <LINK rel="stylesheet" type="text/css" href="./style.css">
  </head>

  <body bgcolor=#FFFFFF text=000000>
  <?php
}

// Function to print page footer
function print_footer() {
  echo "</body>";
  echo "</html>";

}

?>
