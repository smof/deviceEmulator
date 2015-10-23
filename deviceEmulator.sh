#!/bin/bash
#Device Emulator to go through the OAuth2 Device Flow
#Simon.Moffatt@ForgeRock.Com


#Pull in settings from hidden 400 protected file
source .settings

#main menu interface ================================================================================================================================================================================
function menu() { 
	
	clear
	echo "OAuth2 Device Flow - Device Emulator Menu"
	echo "-----------------------------------------"
	echo "1:  Start New Device Flow"
	echo "2:  Check Issued Token Validity"
	echo "3:  Refresh Previously Stored Access Token"
	echo ""
	echo "C:  Configure Emulator Settings"
	echo "X:  Exit"
	echo "-----------------------------------------"
	echo "Select an option:"
	read option

	case $option in

		1)
			startFlow
			;;	

		2)
			checkToken
			;;
			
		3)
			refreshToken
			;;



		[x] | [X])
				clear	
				echo "Device Emulator closed"
				echo ""			
				exit
				;;
		[c] | [C])
				configure
				;;

		*)

			menu
			;;
	esac

}

#Configure settings
function configure(){

	clear
	chmod 600 .settings
	nano .settings
	chmod 400 .settings
	menu

}


#Request to get device code
function startFlow {

	clear
	echo "OAuth2 Device Flow - Initiating Device Request"
	echo "----------------------------------------------"

	#Clear down previously saved device_code
	rm -f .access_token .refresh_token	

	#Create HTTP request to device_code and user_code
	echo "Using client: $CLIENT_ID to get device_code"
	response=$(curl -s --request POST --header "Content-Type: application/json" "$OPENAM_URL/oauth2/device/code?response_type=$RESPONSE_TYPE&scope=$SCOPE&client_id=$CLIENT_ID&nonce=1234")
	#Pull out interesting response variables
	verification_url=$(echo $response | jq .verification_url)
	device_code=$(echo $response | jq .device_code | sed 's/\"//g')
	user_code=$(echo $response | jq .user_code)
	interval=$(echo $response | jq .interval)
	expiration=$(echo $response | jq .expires_in)
	
	#Create interaction
	echo "Go to the following URL: $verification_url"
	echo "Enter the following user_code: $user_code within the next $expiration seconds"
	echo ""

	#Do poll against authorization service
	counter=0
	echo "Polling Authorisation Service for approval with device_code: $device_code"
	#Create while loop to poll the authorisation service
	while true; do
		sleep $interval
		counter=$((counter + $interval))
		echo "Polled $counter seconds"	
		accessTokenResponse=$(curl -s --request POST --header "Content-Type: application/json" "$OPENAM_URL/oauth2/device/token?client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&code=$device_code")
		echo 
		echo $accessTokenResponse | jq .
		#Check if access_token has been sent back or not
		access_token=$(echo $accessTokenResponse | jq '.access_token')
		echo ""
		echo "Access token: $access_token"
		echo ""

		#Check that access_token has been sent back by doing a null check on it
		if [ "$access_token" != "null" ]
		then
			echo ""		
			echo "Consent given!! Access token found..."
			#Save access_token and refresh_token
			echo $accessTokenResponse | jq '.access_token' | sed 's/\"//g' > .access_token	
			echo $accessTokenResponse | jq '.refresh_token' | sed 's/\"//g' > .refresh_token	
			chmod 400 .access_token .refresh_token
			echo ""
			echo "----------------------------------------------"
			echo ""
			read -p "Press [Enter] to return to menu"
			menu
		fi		
	done
}

#Checks previously issued access_token
function checkToken {

	clear
	echo "OAuth2 Device Flow - Check Token Validity"
	echo "-----------------------------------------"

	#Check token exists
	if [ -e .access_token ]
	then
		access_token=$(cat .access_token)
		clientCreds=$(echo "SetTopBox:Passw0rd" | base64) #base64 encoded client creds and secret as set in the OAuth2 client in OpenAM
		checkTokenResponse=$(curl -s --request POST --user "$CLIENT_ID:$CLIENT_SECRET" --header "Content-Type: application/json" "$OPENAM_URL/oauth2/introspect?token=$access_token")
		echo ""
		echo $checkTokenResponse | jq .
		echo ""

	else
		echo ""
		echo "Access Token file not found.  Restart device flow to get token"
		echo ""

	fi

	echo "-----------------------------------------"
	read -p "Press [Enter] to return to menu"
	menu
}

#Refresh a previously store refresh token is access token has expired
function refreshToken {

	clear
	echo "OAuth2 Device Flow - Refresh Token"
	echo "-----------------------------------------"

	#Check refresh token exists
	if [ -e .refresh_token ]
	then

		refresh_token=$(cat .refresh_token)
		PAYLOAD="grant_type=refresh_token&refresh_token=$refresh_token&scope=$SCOPE"
		refreshTokenResponse=$(curl -s --request POST --user "$CLIENT_ID:$CLIENT_SECRET" --data $PAYLOAD "$OPENAM_URL/oauth2/access_token")
		echo ""
		echo $refreshTokenResponse | jq .
		#Save down new tokens - note doing both in case refresh token is also refreshed based on settings in OpenAM
		chmod 600 .refresh_token .access_token
		refresh_token=$(echo $refreshTokenResponse | jq '.refresh_token' | sed 's/\"//g')
		access_token=$(echo $refreshTokenResponse | jq '.access_token' | sed 's/\"//g')
		echo $refresh_token > .refresh_token
		echo $access_token > .access_token
		chmod 400 .access_token .refresh_token

	else
		echo ""
		echo "Refresh Token file not found.  Restart device flow to get token"
	
	fi

	echo ""
	echo "-----------------------------------------"
	read -p "Press [Enter] to return to menu"
	menu
}



#Run Through
menu
