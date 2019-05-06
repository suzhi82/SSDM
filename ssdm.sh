#!/bin/bash


#############################################################################
# Initialization

# Name of this shell and amending tips for checking soft link
PNAME=`ls -l $0 | sed -e 's/\ /\//g'`
SNAME=${PNAME##*/}
ENAME=${0##*/}
#echo $0
#echo PN=$PNAME  # Prepared name
#echo SN=$SNAME  # Script name -- Filename only
#echo EN=$ENAME  # Runtime name -- Maybe soft link name or script name 

# If soft link name does not equal script name then stop the program  
if [[ $PNAME == l* && $SNAME != $ENAME ]]; then
  echo "Illegel soft link name! Please use commands below to rebuild it:"
  echo "sudo rm -rf $0"
  echo "sudo ln -s /${PNAME##*//} ${0%/*}/$SNAME"
  exit -1
fi

# Get running shell name with absolutely basepath for saving status
EPATH=$(cd `dirname $0`; pwd)
XNAME=$EPATH'/'$ENAME
#echo $XNAME  # Running shell's name with absolutely path

# Version
VERSION="$SNAME v1.1.02"

# Set localhost 1st IP address as source address
sip=$(ifconfig | awk '/inet addr:/{split($2, ips, ":"); print ips[2]}' | awk '{if(NR==1) print $1}')

# Password of sudo
pswd="123"

# Previously used data
pucp=0kb

# Total used data
ucp=0


#############################################################################
# Define Functions
EXEC_CMD()
{
  echo "Exec("$@")"
  $@
}

USAGE_HELP()
{
  # String of usage and help with color display
  echo -e "\
  \033[7m Usage: \033[m
  \033[32m\
  \b$SNAME {-v} {-h} {-l} {-i} {-o allow|forbid|clean(all)|view|save target_file [-s Server_IPAddress] -p PORT -c numG|M} [-x SUDOPSWD]\n\
  \033[m \n\
  \033[7m Options: \033[m\033[32m
   -h Help
   -l List daemon processes
   -i List IPs and iptables of server
   -o Operate types
      allow      : Allow limited data through a port
      forbid     : Forbid any data through a port
      clean(all) : Clean iptables and daemon process by conditions or all by cleanall
      view       : View current status
      save       : Save current status to target_file which can be restored in next time
   -s Server IP address
   -p Server port
   -c Data capacity
   -u Used data
   -x Password of sudo
   -v Show Version
  \033[m "
}

LIST_DAEMONS()
{
  ps -ef | grep $SNAME | grep -v "grep" | grep -v "$SNAME \-l"
}

LIST_IPS_IPTABLES()
{
  echo -e "\033[7m Local IPTABLES: \033[m"
  # Switch to sudo and put standard and error output to /dev/null
  echo $pswd | sudo -S date &> /dev/null
  sudo iptables -nvwL --line-number 
  echo
  echo -e "\033[7m Local Source IPs: \033[m"
  ifconfig | awk '/inet addr:/{split($2, ips, ":"); print ips[2]}' | \
    awk '{if(NR==1) print "\033[40;33m"$1" <-- default \033[m"; else print $1}'
}

check_ip_validity()
{
  IP=$1
  VALID_CHECK=$(echo $IP | awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255 {print "yes"}')
  if echo $IP | grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$" > /dev/null; then
    if [ ${VALID_CHECK:-no} == "yes" ]; then
      echo "IP $IP available."
    else
      echo "IP $IP not available!"
      exit 3
    fi
  else
    echo "IP $IP format error!"
    exit 3
  fi
}

is_a_number()
{
  case "$1" in 
    [1-9][0-9]*)  
      #echo "$sport is number."
      return 0
      ;;
    *)  
      echo "$1 is not a number." ; exit 3 ;; 
  esac
}

calculate_capacity()
{
  # Uppercase characters and extract last 1 char or 2 chars as Capacity Unit
  unit=`echo $1 | tr '[a-z]' '[A-Z]'`
  if [ ${unit:0-2} == 'BS' ]; then
    unit=1
  elif [ ${unit:0-1} == 'K' ] || [ ${unit:0-2} == 'KB' ]; then
    unit=1024
  elif [ ${unit:0-1} == 'M' ] || [ ${unit:0-2} == 'MB' ]; then
    unit=1024*1024
  elif [ ${unit:0-1} == 'G' ] || [ ${unit:0-2} == 'GB' ]; then
    unit=1024*1024*1024
  elif [ ${unit:0-1} == 'T' ] || [ ${unit:0-2} == 'TB' ]; then
    unit=1024*1024*1024*1024
  else
    echo "Illegal capacity unit [$unit]"
    exit 3
  fi

  # Remove chars from arg1 leave numbers only 
  num=`echo $1 | tr -d [:alpha:]`
  if [ "x" == "x$num" ]; then
    echo "Illegal capacity number"
    exit 3
  fi

  # Return capacity in byte unit
  echo $num'*'$unit|bc
}

bytes_to_unit()
{
  tmp=$1; mtp=1
  uarr=('BS' 'KB' 'MB' 'GB')

  #is_a_number $tmp

  for((idx=0;idx<${#uarr[@]};idx++)); do
    if(($tmp/1024==0)); then
      break;
    else
      ((tmp=$tmp/1024))
      ((mtp=$mtp*1024))
    fi
  done

  if((idx>0)); then echo $(echo "scale=2; $1/$mtp" | bc)${uarr[$idx]}
  else echo $(echo "$1/$mtp" | bc)${uarr[$idx]}; fi
}

DATA_DAEMON_UNSET()
{
  echo "DATA DAEMON UNSET : $@"
  # If unset daemon caused by EXCESS do nothing or it will kill itself, ${!#} means last arg 
  echo LASTARG=${!#}
  if [ "${!#}" == "EXCESS" ]; then return 0; fi

  # Kill daemon process
  echo "ps -ef | grep $SNAME | grep -v 'grep' | grep '-p $2' | awk '\$3==1 {print \$2}'"
  IDS=`ps -ef | grep "$SNAME" | grep -v 'grep' | grep "\-p $2" | awk '$3==1 {print $2}'`  
  echo "DAEMON_IDs={$IDS}"
  for id in $IDS; do kill -9 $id; done
}

DataSupervisor_clean()
{
  echo "clean func : $@"
  # Switch to sudo and put standard and error output to /dev/null
  echo $pswd | sudo -S date &> /dev/null

  # Clean the rules in OUTPUT
  echo "Cleaning OUTPUT ACCEPT"
  while (($?==0)); do
    EXEC_CMD sudo iptables -D OUTPUT -s $1 -p tcp --sport $2 -j ACCEPT
  done

  echo "Cleaning OUTPUT DROP"
  while (($?==0)); do
    EXEC_CMD sudo iptables -D OUTPUT -s $1 -p tcp --sport $2 -j DROP
  done

  # Clean the rules in INPUT
  echo "Cleaning INPUT ACCEPT"
  while (($?==0)); do
    EXEC_CMD sudo iptables -D INPUT -d $1 -p tcp --dport $2 -j ACCEPT
  done

  echo "Cleaning INPUT DROP"
  while (($?==0)); do
    EXEC_CMD sudo iptables -D INPUT -d $1 -p tcp --dport $2 -j DROP
  done

  # Unset daemon process
  DATA_DAEMON_UNSET $@

  echo "Cleaning INPUT/OUTPUT rules and killing daemon process done!!!"
}

DataSupervisor_cleanall()
{
  echo "cleanall func : $@"

  # Display all daemon processes
  ps -ef | grep $SNAME | grep -v "grep" | grep "allow" | awk '{ for(i=1; i<=8; i++){ $i="" }; print "dps["NR-1"]=\""$0"\"" }'

  # Same command like above to build a array
  eval $(ps -ef | grep $SNAME | grep -v "grep" | grep "allow" | awk '{ for(i=1; i<=8; i++){ $i="" }; print "dps["NR-1"]=\""$0"\"" }')

  # Display the count of array 'dsp'
  echo "\${#dps[@]}="${#dps[@]}

  # Analyze option of daemon processes
  for((i=0;i<${#dps[@]};i++)); do
    eval set -- ${dps[i]}
    while(($#>0)); do
      case "$1" in
        '-s') sip=$2; shift 2 ;;
        '-p') sport=$2; shift 2 ;;
        *) shift ;; 
      esac
    done

    # Invoke clean operate with parsed arguments
    EXEC_CMD DataSupervisor_clean $sip $sport
  done

}

DataSupervisor_forbid()
{
  echo "forbid func : $@"
  # Switch to sudo and put standard and error output to /dev/null
  echo $pswd | sudo -S date &> /dev/null

  # Clean old rules and daemon processes
  DataSupervisor_clean $@
  
  # Add new rules
  EXEC_CMD "sudo iptables -A INPUT -d $1 -p tcp --dport $2 -j DROP"
  EXEC_CMD "sudo iptables -A OUTPUT -s $1 -p tcp --sport $2 -j DROP"

  echo "Setting forbidden rules done!!!"
}

DATA_DAEMON_SET()
{
  echo "DATA DAEMON SET : $@"
  # Switch to sudo and put standard and error output to /dev/null
  echo $pswd | sudo -S date &> /dev/null

  while true; do
    # Check the 1st iptables rule ONLY
    eval $(sudo iptables -nxvwL OUTPUT | awk -v PUCP=$4 '$3=="ACCEPT"&&$8=="'$1'"&&$11=="spt:'$2'" {print "ucp="$2+PUCP; exit 0}')

    # Record to temp file
    echo $ucp > /tmp/_"$sip"_"$sport"

    # Compare with capacity
    if (($ucp>=$3)); then
      DataSupervisor_forbid $@ "EXCESS"
      exit 0
    fi 

    sleep 1
  done
}

DataSupervisor_allow()
{
  echo "allow func : $@"
  # Switch to sudo and put standard and error output to /dev/null
  echo $pswd | sudo -S date &> /dev/null

  # Clean old rules and daemon processes
  DataSupervisor_clean $@
  
  # Add new rules
  EXEC_CMD "sudo iptables -A INPUT -d $1 -p tcp --dport $2 -j ACCEPT"
  EXEC_CMD "sudo iptables -A OUTPUT -s $1 -p tcp --sport $2 -j ACCEPT"

  # Set daemon process
  DATA_DAEMON_SET $@ &

  sleep 1
  echo "Adding rules and setting daemon process done!!!"
}

DataSupervisor_view()
{
  # Switch to sudo and put standard and error output to /dev/null
  echo $pswd | sudo -S date &> /dev/null

  SFLAG=$1

  if [ "$SFLAG" != "SAVE" ]; then
    echo "view func : $@"
    #clear
    #EXEC_CMD "sudo iptables -nvwL --line-number"
    EXEC_CMD "sudo iptables -nw -L INPUT"
    EXEC_CMD "sudo iptables -nw -L OUTPUT"
  fi

  # To build a array of daemon processes' detail
  eval $(ps -ef | grep $SNAME | grep -v "grep" | grep "allow" | sort -k13 | awk '$3==1 { for(i=1; i<=8; i++){ $i="" }; print "dps["NR-1"]=\""$0"\"" }')

  # Display the count of array 'dsp'
  if [ "$SFLAG" != "SAVE" ]; then echo "\${#dps[@]}="${#dps[@]}; fi

  # Store iptables result to temp file
  tmpf="/tmp/_9527.9527_"
  sudo iptables -nvwL OUTPUT > $tmpf

  # Analyze option of daemon processes
  for((i=0;i<${#dps[@]};i++)); do
    eval set -- ${dps[i]}
    while(($#>0)); do
      case "$1" in
        '-s') sip=$2; shift 2 ;;
        '-p') sport=$2; shift 2 ;;
        '-c') cpct=`echo $2 | tr [a-z] [A-Z]`; shift 2 ;;
        *) shift ;; 
      esac
    done

    # Read used bytes count from file until have content
    while true; do
      ucp=`head -1 /tmp/_"$sip"_"$sport"`
      if [ "x$ucp" != "x" ]; then break; fi 
    done

    # Print matched results
    if [ "$SFLAG" != "SAVE" ]; then
      ucp=`bytes_to_unit $ucp`
      # Quote var from shell global to awk needs -- "'"$abc"'"
      awk '$3=="ACCEPT"&&$8=="'"$sip"'"&&$11=="'"spt:$sport"'" {print $3"--"$8"--"$11"--'"$ucp/$cpct"'"}' $tmpf
    else
      # Showing the ALLOW commands
      ucp=$ucp'BS'
      echo "$XNAME -o allow -s $sip -p $sport -c $cpct -u $ucp"
    fi
  done

  if [ "$SFLAG" == "SAVE" ]; then
    # Showing the FORBID commands
    sed s/spt:// $tmpf | awk -v XNAME=$XNAME '$3=="DROP" {print XNAME " -o forbid -s " $8 " -p " $11}'
    echo "DROP CMDS ..."
  fi
 
}

DataSupervisor_save()
{
  #echo "save func : $@"
  DataSupervisor_view "SAVE"
}

DataSupervisor()
{
  # Invoke different function by subname
  EXEC_CMD eval "${FUNCNAME[0]}_$1" $2 $3 $4 $5
}



#############################################################################
# Obtain arguments
# No colon after character means the option with no parameter
while getopts "o:s:p:c:u:x:ilhv" arg
do
  # Parameter stored in $OPTARG
  case $arg in
    o)
      # Operate Type
      # In eval \$\_$arg equals var $_o, ':-' means using default value when var is not defined or is empty. 
      eval [[ \$\{\_$arg\:\-UNSET\} != "UNSET" ]] \
        && { echo "Duplicated option -$arg "; exit 1; } \
        || { oprt="$OPTARG"; eval \_$arg="SET"; } ;;
    s)
      # Server IP 
      eval [[ \$\{\_$arg\:\-UNSET\} != "UNSET" ]] \
        && { echo "Duplicated option -$arg "; exit 1; } \
        || { sip="$OPTARG"; eval \_$arg="SET"; } ;;
    p)
      # Server Port
      eval [[ \$\{\_$arg\:\-UNSET\} != "UNSET" ]] \
        && { echo "Duplicated option -$arg "; exit 1; } \
        || { sport="$OPTARG"; eval \_$arg="SET"; } ;;
    c)
      # Data Limit
      eval [[ \$\{\_$arg\:\-UNSET\} != "UNSET" ]] \
        && { echo "Duplicated option -$arg "; exit 1; } \
        || { cpct="$OPTARG"; eval \_$arg="SET"; } ;;
    u)
      # Used data last time
      eval [[ \$\{\_$arg\:\-UNSET\} != "UNSET" ]] \
        && { echo "Duplicated option -$arg "; exit 1; } \
        || { pucp="$OPTARG"; eval \_$arg="SET"; } ;;
    x)
      # Password of sudo
      eval [[ \$\{\_$arg\:\-UNSET\} != "UNSET" ]] \
        && { echo "Duplicated option -$arg "; exit 1; } \
        || { pswd="$OPTARG"; eval \_$arg="SET"; } ;;
    l)
      # List Data Daemon Process
      LIST_DAEMONS ; exit 0 ;;
    i)
      # For Display Localhost IPs and iptables
      LIST_IPS_IPTABLES ; exit 0 ;;
    v)
      # For Display Localhost IPs and iptables
      echo $VERSION ; exit 0
      ;;
    # All unknown arguments treated as '?' by getopts
    ?) 
      USAGE_HELP ; exit 1 ;;
  esac
done


#############################################################################
# Main Program

# Check -o viewall
if [ "$oprt" == "view" ]; then
  DataSupervisor_view
  exit 0

elif [ "$oprt" == "cleanall" ]; then
  DataSupervisor_cleanall
  exit 0

elif [ "$oprt" == "save" ]; then
  DataSupervisor_save $@
  exit 0

# Check necssary options
elif [ "x$oprt" == "x" ] || [ "x$sip" == "x" ] || [ "x$sport" == "x" ] ; then
  echo "Missing essential options and arguments -o and -p"
  USAGE_HELP ; exit 1

# Check -o in clean | view | forbid
elif [ "$oprt" == "clean" ] || [ "$oprt" == "view" ] || [ "$oprt" == "forbid" ]; then
  eval DataSupervisor_$oprt $sip $sport
  exit 0

# Check arg of data capacity 
elif [ "$oprt" == "allow" ] && [ "x$cpct" == "x" ] ; then
  echo "Missing essential option and argument -c"
  USAGE_HELP ; exit 1

fi

# Check IP address validity
rtn=`check_ip_validity $sip`
[ $? -eq 0 ] || { echo $rtn; exit 3; }

# Check Port validity
rtn=`is_a_number $sport`
[ $? -eq 0 ] || { echo $rtn; exit 3; }

# Calculate exactly bytes
rtn=`calculate_capacity $cpct`
[ $? -eq 0 ] && cpct=$rtn || { echo $rtn; exit 3; }

# Calculate exactly previously used bytes
rtn=`calculate_capacity $pucp`
[ $? -eq 0 ] && pucp=$rtn || { echo $rtn; exit 3; }

# Display checked results
echo Operate_Type=$oprt
echo Server_IP=$sip
echo Server_Port=$sport
echo Data_Limit=$cpct'(bytes)'
echo Used_Data=$pucp'(bytes)'

# Identify operate type
case $oprt in 
  allow | forbid | clean | cleanall | view )
    DataSupervisor $oprt $sip $sport $cpct $pucp
    ;; 
  *)
    echo "Unknown operate type - $oprt"
    USAGE_HELP ; exit 4 ;;
esac



#############################################################################

