#!/bin/bash

####################################################################################################
#
# Copyright (c) 2014, JAMF Software, LLC.  All rights reserved.
#
#       Redistribution and use in source and binary forms, with or without
#       modification, are permitted provided that the following conditions are met:
#               * Redistributions of source code must retain the above copyright
#                 notice, this list of conditions and the following disclaimer.
#               * Redistributions in binary form must reproduce the above copyright
#                 notice, this list of conditions and the following disclaimer in the
#                 documentation and/or other materials provided with the distribution.
#               * Neither the name of the JAMF Software, LLC nor the
#                 names of its contributors may be used to endorse or promote products
#                 derived from this software without specific prior written permission.
#
#       THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#       EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#       WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#       DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#       DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#       (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#       LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#       ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#       (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#       SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
####################################################################################################
#
#	DESCRIPTION
#
#	This script was designed to read full JSS Summaries generated from version 9+.
#	The script will parse through the summary and return back a set of data that
#	should be useful when performing JSS Health Checks.
#
####################################################################################################
# 
#	HISTORY
#
#	Version 1.0 Created by Sam Fortuna on June 13th, 2014
#	Version 1.1 Updated by Sam Fortuna on June 17th, 2014
#		-Fixed issues with parsing some data types
#		-Added comments for readability
#		-Added output about check-in information
#		-Added database size parsing
#
#	Version 1.2 Updated by Nick Anderson August 4, 2014
#		-Added recommendations to some displayed items
#	Version 1.3 Updated by Nick Anderson on October 14, 2014
#		-Fixed the way echo works in some terminals
#	Version 1.4a Updated by Nick Anderson
#		-Implement a scaling system fitted to individual preference
#		-Check certificate expiration dates
#
#	TODO Re-order items to match most common workflows
#	TODO Recommend minimum tomcat memory (cannot read from summary)
#	TODO Check log file location
#	TODO Include check-in frequency and number of cluster nodes in recommendation formula
#	TODO Do not show SSL expiration days unless able to read the date (issue with third party certs in the summary)
#	TODO Bring packet size up for some other reasons
#
####################################################################################################

# only you can choose your path (unless you leave it at the default)
#echo "The scaling formula can be changed with the variable 'recset' in the script"

#Enter the path to the JSS Summary (cannot includes spaces)
read -p "Summary Location: " file
#file="/Users/nickanderson/Desktop/jssSummary-1410804159149.txt "

# amanda -- bracketed method with direct recommendations
# jonnygrant -- 20% of number of devices for pool size
#recset="jonnygrant"

read -p "Select jonnygrant or amanda scaling method: " recset

#Option to read in the path from Terminal
if [[ "$file" == "" ]]; then
	echo "Please enter the path to the JSS Summary file (currently does not support paths with spaces)"
	read file
fi

#Verify we can read the file
data=`cat $file`
if [[ "$data" == "" ]]; then
	echo "Unable to read the file path specified"
	echo "Ensure there are no spaces and that the path is correct"
	exit 1
fi

# check to see what kind of terminal this is to make sure we use the right echo mode, no idea why some are different in this aspect
echotest=`echo -e "test"`
if [[ "$echotest" == "test" ]] ; then
	echomode="-e"
else
	echomode=""
fi


#Gathers smaller chunks of the whole summary to make parsing easier

#Get the first 75 lines of the Summary
basicInfo=`head -n 75 $file`
#Find the line number that includes clustering information
lineNum=`cat $file | grep -n "Clustering Enabled" | awk -F : '{print $1}'`
#Store 100 lines after clustering information
subInfo=`head -n $(($lineNum + 100)) $file | tail -n 101`
#Find the line number for the push certificate Subject (used to get the expiration)
pushExpiration=`echo "$subInfo" | grep -n "com.apple.mgmt" | awk -F : '{print $1}'`
#Find the line number that includes checkin frequency information
lineNum=`cat $file | grep -n "Check-in Frequency" | awk -F : '{print $1}'`
#Store 30 lines after the Check-in Frequency information begins
checkInInfo=`head -n $(($lineNum + 30)) $file | tail -n 31`
#Store last 300 lines to check database table sizes
dbInfo=`tail -n 300 $file`
# Determine whether clustering is enabled
clustering=`echo "$subInfo" | awk '/Clustering Enabled/ {print $NF}'`
# Find the models of printers and determine whether none, some, or xerox for max packet size
findprinters=`cat $file | grep -B 1 "CUPS Name" | grep -v "CUPS Name"`
xeroxprinters=`echo $findprinters | grep "Xerox"`
# Add up the number of devices we have so we can make recommendations
computers=`echo "$basicInfo" | awk '/Managed Computers/ {print $NF}'`
mobiles=`echo "$basicInfo" | awk '/Managed Mobile Devices/ {print $NF}'`
totaldevices="$(( $computers + $mobiles ))"
# Find today's unix epoch time to help with our certificate expiration calculation
todayepoch=`date +"%s"`


# Select Amanda or Jonny / Grant Hybrid Recommendation Set
if [[ "$recset" = "amanda" ]] ; then

	# Sort our summary into a performance bracket based on number of devices total
	if (( $totaldevices < 301 )) ; then
		echo "Bracket shown for 1-300 Devices"
		poolsizerec="150"
		sqlconnectionsrec="151"
		httpthreadsrec="453"
		clusterrec="Unnecessary"
		maxpacketrec="512MB"
	else
		if (( $totaldevices < 601 )) ; then
			echo "Bracket shown for 301-600 Devices"
			poolsizerec="150"
			sqlconnectionsrec="301 X Number of cluster nodes"
			httpthreadsrec="753 X Number of cluster nodes"
			clusterrec="Unnecessary"
			maxpacketrec="512MB"
		else
			if (( $totaldevices < 1001)) ; then
				echo "Bracket shown for 601-1000 Devices"
				poolsizerec="150"
				sqlconnectionsrec="601 X Number of cluster nodes"
				httpthreadsrec="1503 X Number of cluster nodes"
				clusterrec="Consider Load Balancing"
				maxpacketrec="1024MB"
			else
				if (( $totaldevices < 2001 )) ; then
					echo "Bracket shown for 1001-2000 Devices"
					poolsizerec="300"
					sqlconnectionsrec="801 X Number of cluster nodes"
					httpthreadsrec="2003 X Number of cluster nodes"
					clusterrec="Seriously consider Load Balancing"
					maxpacketrec="1024MB"
				else
					if (( $totaldevices < 5001 )) ; then
						echo "Bracket shown for 2001-5000 Devices"
						poolsizerec="300"
						sqlconnectionsrec="1001 X Number of cluster nodes"
						httpthreadsrec="2503 X Number of cluster nodes"
						clusterrec="Load Balancing"
						maxpacketrec="1024MB"
					else
						echo "Bracket shown for > 5000 Devices. SO MANY DEVICES."
						poolsizerec="300 (or more)"
						sqlconnectionsrec="1001 (or more) X Number of cluster nodes"
						httpthreadsrec="2503 (or more) X Number of cluster nodes"
						clusterrec="Load Balancing"
						maxpacketrec="1024MB"
					fi
				fi
			fi
		fi
	fi


elif [[ "$recset" = "jonnygrant" ]] ; then

	echo "FBwn for $totaldevices devices."
	# If clustering is enabled, ask how many nodes there are (default 2, because clustering)
	if [[ "$clustering" = "true" ]] ; then
		read -p "Clustering detected. Cluster node count: " clusternodes
		clusternodes=${clusternodes:-2}
	else
		clusternodes=${clusternodes:-1}
	fi

	# set the pool size to x percent of our total devices
	poolsize=`python -c "print round($totaldevices*.2)" | sed 's/\..*//'`

	#Have a minimum pool size so that we're not recommending something crazy like 6 connections
	if (( "$poolsize" < 90 )) ; then
		poolsizerec="90"
	else
		poolsizerec="$poolsize"
	fi

	# number of cluster nodes set by detection of clustering and prompt * minimum or recommended pool size + 10
	sqlconnectionsrec=`python -c "print $clusternodes*$poolsizerec+10"` # python style order of operations ONLY
	# number of sql connections * 2.5 (cluster nodes already factored into sql connections)
	httpthreadsrec=`python -c "print round($sqlconnectionsrec*2.5)" | sed 's/\..*//'`
	# this doesn't do anything yet obviously
	clusterrec=""
	# find the current max packet size for our maxpacket-in-relation-to-current-setting-and-printers logic
	curmaxpacket=`echo $echomode "$(($(echo "$basicInfo" | awk '/max_allowed_packet/ {print $NF}')/ 1048576))"`


	if [[ "$findprinters" == "" ]] ; then						#If we found no printers, then
		if (( $curmaxpacket < 17 && $totaldevices < 500 )) ; then		#check to see if our current packet size is lower or equal to 16
			maxpacketrec="16 MB"					#if it is lower or recommended, recommend 16
		elif (( $curmaxpacket > 15 && $totaldevices < 500)) ; then		#if it's higher than recommended
			maxpacketrec="Current Setting"				#don't change it
		elif (( $curmaxpacket < 129 && $totaldevices < 1000 )) ; then	#rinse and repeat if we have over 500 devices
			maxpacketrec="128 MB"
		elif (( $curmaxpacket > 127 && $totaldevices < 1000)) ; then
			maxpacketrec="Current Setting"
		elif (( $curmaxpacket < 255 && $totaldevices < 2000 )) ; then
			maxpacketrec="256MB"
		elif (( $curmaxpacket > 257 && $totaldevices < 2000 )) ; then
			maxpacketrec="Current Setting"
		fi
	elif [[ "$xeroxprinters" != "" ]] ; then						#then if the return for searching 'xerox' isn't blank
		maxpacketrec="512 MB"						#recommend a giant packet size
	elif [[ "$findprinters" != "" ]] ;then						#but if they're other brand printers
		maxpacketrec="256 MB"						#just increase packet size to 256
	else
		maxpacketrec="Unable to determine"				#"slightly better than a blank result"
	fi

else
	# THERE CAN ONLY BE ONE
	echo "WARN: No scaling method set."

fi


#Parse the data and print out the results
echo $echomode "JSS Version: \t\t\t\t $(echo "$basicInfo" | awk '/Installed Version/ {print $NF}')"
echo $echomode "Managed Computers: \t\t\t $(echo "$basicInfo" | awk '/Managed Computers/ {print $NF}')"
echo $echomode "Managed Mobile Devices: \t\t $(echo "$basicInfo" | awk '/Managed Mobile Devices/ {print $NF}')"
echo $echomode "Server OS: \t\t\t\t $(echo "$basicInfo" | grep "Operating System" | awk '{for (i=3; i<NF; i++) printf $i " "; print $NF}')"
echo $echomode "Java Version: \t\t\t\t $(echo "$basicInfo" | awk '/Java Version/ {print $NF}')"
echo $echomode "Database Size: \t\t\t\t $(echo "$basicInfo" | grep "Database Size" | awk 'NR==1 {print $(NF-1),$NF}')"
echo $echomode "Maximum Pool Size:  \t\t\t $(echo "$basicInfo" | awk '/Maximum Pool Size/ {print $NF}') \t$(tput setaf 2)Recommended: $poolsizerec$(tput sgr0)"
echo $echomode "Maximum MySQL Connections: \t\t $(echo "$basicInfo" | awk '/max_connections/ {print $NF}') \t$(tput setaf 2)Recommended: $sqlconnectionsrec$(tput sgr0)"

# alert if binary logging is enabled
binlogging=`echo "$basicInfo" | awk '/log_bin/ {print $NF}'`
if [ "$binlogging" = "OFF" ] ; then
	echo $echomode "Bin Logging: \t\t\t\t $(echo "$basicInfo" | awk '/log_bin/ {print $NF}') \t$(tput setaf 2)✓$(tput sgr0)"
else
	echo $echomode "Bin Logging: \t\t\t\t $(echo "$basicInfo" | awk '/log_bin/ {print $NF}') \t$(tput setaf 9)[!]$(tput sgr0)"
fi
echo $echomode "Max Allowed Packet Size: \t\t $(($(echo "$basicInfo" | awk '/max_allowed_packet/ {print $NF}')/ 1048576)) MB \t$(tput setaf 2)Recommended: $maxpacketrec$(tput sgr0)"
echo $echomode "MySQL Version: \t\t\t\t $(echo "$basicInfo" | awk '/version ..................../ {print $NF}')"

# alert user to clustering recommendation if set to 'amanda' if not enabled, otherwise warn user if enabled
if [[ "$clustering" = "false" && "$recset" = "amanda" ]] ; then
	echo $echomode "Clustering Enabled: \t\t\t $(echo "$subInfo" | awk '/Clustering Enabled/ {print $NF}') \t$(tput setaf 2)Recommended: $clusterrec$(tput sgr0)"
elif [ "$clustering" = "true" ] ; then
	echo $echomode "Clustering Enabled: \t\t\t $(echo "$subInfo" | awk '/Clustering Enabled/ {print $NF}') \t$(tput setaf 9)[!]$(tput sgr0)"
else
	echo $echomode "Clustering Enabled: \t\t\t $(echo "$subInfo" | awk '/Clustering Enabled/ {print $NF}') \t$(tput setaf 9)$(tput sgr0)"
fi

# alert user to change management being disabled
changemanagement=`echo "$subInfo" | awk '/Use Log File/ {print $NF}'`
if [ $changemanagement = false ] ; then
	echo $echomode "Change Management Enabled: \t\t $(echo "$subInfo" | awk '/Use Log File/ {print $NF}') \t$(tput setaf 2)Recommended: On$(tput sgr0)"
else
	echo $echomode "Change Management Enabled: \t\t $(echo "$subInfo" | awk '/Use Log File/ {print $NF}') \t$(tput setaf 2)✓$(tput sgr0)"
fi
echo $echomode "Log File Location: \t\t\t $(echo "$subInfo" | awk -F . '/Location of Log File/ {print $NF}')"

# search for the built-in name in the SSL subject, if it is not detected it must be a third party cert or broken so alert user
sslsubject=`echo "$subInfo" | awk '/SSL Cert Subject/ {$1=$2=$3="";print $0}' | grep "O=JAMF Software"`
if [ "$sslsubject" = "" ] ; then
	echo $echomode "SSL Certificate Subject: \t      $(echo "$subInfo" | awk '/SSL Cert Subject/ {$1=$2=$3="";print $0}') \t$(tput setaf 9)[!]$(tput sgr0)"
else
	echo $echomode "SSL Certificate Subject: \t      $(echo "$subInfo" | awk '/SSL Cert Subject/ {$1=$2=$3="";print $0}')"
fi

ssldate=`echo "$subInfo" | awk '/SSL Cert Expires/ {print $NF}'`	#get the current ssl expiration date
sslepoch=`date -jf "%Y/%m/%d %H:%M" "$ssldate 00:00" +"%s"`	#convert it to unix epoch
ssldifference=`python -c "print $sslepoch-$todayepoch"`		#subtract ssl epoch from today's epoch
sslresult=`python -c "print $ssldifference/86400"`			#divide by number of seconds in a day to get remaining days to expiration
# if ssl is expiring in under 60 days, output remaining days in red instead of green
if (( $sslresult > 60 )) ; then
	echo $echomode "SSL Certificate Expiration: \t\t $(echo "$subInfo" | awk '/SSL Cert Expires/ {print $NF}') \t$(tput setaf 2)$sslresult Days$(tput sgr0)"
else
	echo $echomode "SSL Certificate Expiration: \t\t $(echo "$subInfo" | awk '/SSL Cert Expires/ {print $NF}') \t$(tput setaf 9)$sslresult Days$(tput sgr0)"
fi

echo $echomode "HTTP Threads: \t\t\t\t $(echo "$subInfo" | awk '/HTTP Connector/ {print $NF}') \t$(tput setaf 2)Recommended: $httpthreadsrec$(tput sgr0)"
echo $echomode "HTTPS Threads: \t\t\t\t $(echo "$subInfo" | awk '/HTTPS Connector/ {print $NF}') \t$(tput setaf 2)Recommended: $httpthreadsrec$(tput sgr0)"
echo $echomode "JSS URL: \t\t\t\t $(echo "$subInfo" | awk '/HTTPS URL/ {print $NF}')"

apnsdate=`echo "$subInfo" | grep "Expires" | awk 'NR==3 {print $NF}'`	#get the current apns expiration date
apnsepoch=`date -jf "%Y/%m/%d %H:%M" "$apnsdate 00:00" +"%s"`	#convert it to unix epoch
apnsdifference=`python -c "print $apnsepoch-$todayepoch"`		#subtract apns epoch from today's epoch
apnsresult=`python -c "print $apnsdifference/86400"`			#divide by number of seconds in a day to get remaining days to expiration
# if apns is expiring in under 60 days, output remaining days in red instead of green
if (( $apnsresult > 60 )) ; then
	echo $echomode "APNS Expiration: \t\t\t $(echo "$subInfo" | grep "Expires" | awk 'NR==3 {print $NF}') \t$(tput setaf 2)$apnsresult Days$(tput sgr0)"
else
	echo $echomode "APNS Expiration: \t\t\t $(echo "$subInfo" | grep "Expires" | awk 'NR==3 {print $NF}') \t$(tput setaf 9)$apnsresult Days$(tput sgr0)"
fi

# detect whether external CA is enabled and warn user
thirdpartycert=`echo "$subInfo" | awk '/External CA enabled/ {print $NF}'`
if [ $thirdpartycert = false ] ; then
	echo $echomode "External CA Enabled: \t\t\t $(echo "$subInfo" | awk '/External CA enabled/ {print $NF}')"
else
	echo $echomode "External CA Enabled: \t\t\t $(echo "$(tput setaf 3)$subInfo" | awk '/External CA enabled/ {print $NF}') \t$(tput setaf 9)[!]$(tput sgr0)"
fi
echo $echomode "Log Flushing Time: \t\t\t $(echo "$subInfo" | grep "Each Day" | awk '{for (i=7; i<NF; i++) printf $i " "; print $NF}') \t$(tput setaf 2)Recommended: Stagger time from nightly backup$(tput sgr0)"

# check how many logs are set to flush and if 0 display a check
logflushing=`echo "$subInfo" | awk '/Do not flush/ {print $0}' | wc -l`
if ! (( $logflushing < 1 )) ; then
	echo $echomode "Number of logs set to NOT flush:  $(echo "$subInfo" | awk '/Do not flush/ {print $0}' | wc -l) \t$(tput setaf 2)Recommended: Enable log flushing$(tput sgr0)"
else
	echo $echomode "Number of logs set to NOT flush:  $(echo "$subInfo" | awk '/Do not flush/ {print $0}' | wc -l) \t$(tput setaf 2)✓$(tput sgr0)"
fi
# add up the number of logs set to not flush in under 3 months (includes logs set not to flush)
logflushing6months=`echo "$subInfo" | awk '/6 month/ {print $0}' | wc -l`
logflushing1year=`echo "$subInfo" | awk '/1 year/ {print $0}' | wc -l`
notlogflushing3months="$(( $logflushing6months + $logflushing1year + $logflushing ))"
# if all logs are set to flush under 3 months display a check
if ! (( $notlogflushing3months < 1 )) ; then
	echo $echomode "Logs not flushing in under 3 months:     $notlogflushing3months \t$(tput setaf 2)Recommended: Shorten log flushing time$(tput sgr0)"
else
	echo $echomode "Logs not flushing in  under 3 months:    $notlogflushing3months \t$(tput setaf 2)✓$(tput sgr0)"
fi

echo $echomode "Check in Frequency: \t\t\t $(echo "$checkInInfo" | awk '/Check-in Frequency/ {print $NF}')"
echo $echomode "Login/Logout Hooks enabled: \t\t $(echo "$checkInInfo" | awk '/Logout Hooks/ {print $NF}')"
echo $echomode "Startup Script enabled: \t\t $(echo "$checkInInfo" | awk '/Startup Script/ {print $NF}')"
echo $echomode "Flush history on re-enroll: \t\t $(echo "$checkInInfo" | awk '/Flush history on re-enroll/ {print $NF}')"
echo $echomode "Flush location info on re-enroll: \t $(echo "$checkInInfo" | awk '/Flush location information on re-enroll/ {print $NF}')"

# warn user if push notifications are disabled
pushnotifications=`echo "$checkInInfo" | awk '/Push Notifications Enabled/ {print $NF}'`
if [ "$pushnotifications" = "true" ] ; then
	echo $echomode "Push Notifications enabled: \t\t $(echo "$checkInInfo" | awk '/Push Notifications Enabled/ {print $NF}')"
else
	echo $echomode "Push Notifications enabled: \t\t $(echo "$checkInInfo" | awk '/Push Notifications Enabled/ {print $NF}') \t$(tput setaf 9)[!]$(tput sgr0)"
fi


#Check for database tables over 1 GB in size
echo "Tables over 1 GB in size:"
echo "$(echo "$dbInfo" | awk '/GB/ {print $1, "\t", "\t", $(NF-1), $NF}')"

#Find problematic policies that are ongoing, enabled, update inventory and have a scope defined
list=`cat $file| grep -n "Ongoing" | awk -F : '{print $1}'`

echo "The following policies are Ongoing, Enabled and update inventory:"

for i in $list 
do

	#Check if policy is enabled
	test=`head -n $i $file | tail -n 13`
	enabled=`echo "$test" | awk /'Enabled/ {print $NF}'`
	
	#Check if policy has an active trigger
	if [[ "$enabled" == "true" ]]; then
		trigger=`echo "$test" | grep Triggered | awk '/true/ {print $NF}'`
	fi
		
	#Check if the policy updates inventory
	if [[ "$enabled" == "true" ]]; then
		line=$(($i + 35))
		inventory=`head -n $line $file | tail -n 5 | awk '/Update Inventory/ {print $NF}'`
	fi
	
	#Get the scope
	scope=`head -n $(($i + 5)) $file |tail -n 5 | awk '/Scope/ {$1=""; print $0}'`
		
		#Get the name of the policy
		if [[ "$trigger" == "true" && "$inventory" == "true" ]]; then
			name=`echo "$test" | awk -F . '/Name/ {print $NF}'`
			echo "Name: $name" 
			echo "Scope: $scope"
		fi
done


exit 0
