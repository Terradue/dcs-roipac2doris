#!/bin/bash
 
# source the ciop functions (e.g. ciop-log)
source ${ciop_job_include}

# define the exit codes
SUCCESS=0
ERR_AUX=4
ERR_VOR=6
ERR_INVALIDFORMAT=2
ERR_NOIDENTIFIER=5
ERR_NODEM=7

# add a trap to exit gracefully
function cleanExit ()
{
local retval=$?
local msg=""
case "$retval" in
$SUCCESS) msg="Processing successfully concluded";;
$ERR_AUX) msg="Failed to retrieve auxiliary products";;
$ERR_VOR) msg="Failed to retrieve orbital data";;
$ERR_INVALIDFORMAT) msg="Invalid format must be roi_pac or gamma";;
$ERR_NOIDENTIFIER) msg="Could not retrieve the dataset identifier";;
$ERR_NODEM) msg="DEM not generated";;
*) msg="Unknown error";;
esac
[ "$retval" != "0" ] && ciop-log "ERROR" "Error $retval - $msg, processing aborted" || ciop-log "INFO" "$msg"
exit $retval
}
trap cleanExit EXIT


function getAUXref() {
  local rdf=$1
  local ods=$2
  startdate="`ciop-casmeta -f "ical:dtstart" $rdf | tr -d "Z"`"
  stopdate="`ciop-casmeta -f "ical:dtend" $rdf | tr -d "Z"`"
  opensearch-client -f Rdf -p "time:start=$startdate" -p "time:end=$stopdate" $ods
}


# create a shorter TMPDIR name for some ROI_PAC scripts/binaires 
UUIDTMP="/tmp/`uuidgen`"
ln -s $TMPDIR $UUIDTMP

export TMPDIR=$UUIDTMP

# prepare ROI_PAC environment variables
export INT_BIN=/usr/bin/
export INT_SCR=/usr/share/roi_pac
export PATH=${INT_BIN}:${INT_SCR}:${PATH}

export SAR_ENV_ORB=$TMPDIR/aux
export VOR_DIR=$TMPDIR/vor
export INS_DIR=$SAR_ENV_ORB

export PATH=$_CIOP_APPLICATION/roipac2doris/bin:$PATH

# get the catalogue access point
cat_osd_root="`ciop-getparam aux_catalogue`"

while read input
do
  ciop-log "INFO" "dealing with $input"
  for aux in ASA_CON_AX ASA_INS_AX ASA_XCA_AX ASA_XCH_AX
  do
    ciop-log "INFO" "Getting a reference to $aux"
    for url in `getAUXref $input $cat_osd_root/$aux/description`
    do
      ciop-log "INFO" "the url is $url"
      echo $url | ciop-copy -O $SAR_ENV_ORB -
    done
  done

  # DOR_VOR_AX
  ciop-log "INFO" "Getting a reference to DOR_VOR_AX"
  ref=`getAUXref $input $cat_osd_root/DOR_VOR_AX/description`
  echo $ref | ciop-copy -O $VOR_DIR -
  
  # get the date in format YYMMDD
  sar_date=`ciop-casmeta -f "ical:dtstart" $input | cut -c 3-10 | tr -d "-"`
  sar_date_short=`echo $sar_date | cut -c 1-4`
  ciop-log "INFO" "SAR date: $sar_date and $sar_date_short"

  # get the dataset identifier
  sar_identifier=`ciop-casmeta -f "dc:identifier" $sar_url`
  ciop-log "INFO" "SAR identifier: $sar_identifier"
  sar_folder=$TMPDIR/workdir/$sar_date
  mkdir -p $sar_folder

  # get ASAR products
  sar="`ciop-copy -o $sar_folder $input`"
  cd $sar_folder

  ciop-log "INFO" "Invoke ROI_PAC make_raw_envi.pl"
  make_raw_envi.pl $sar_identifier DOR $sar_date 1>&2
  
  ciop-log "INFO" "Invoke roipac2doris"
  roipac2doris $sar_date  
  
done

