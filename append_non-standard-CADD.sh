#!/bin/bash
#
#  append_non-standard-CADD.sh
#  This script adds to the UDP's local database of non-standard CADD scores
#  INPUTS: current non-standard file, file of non-standard scores to be appended
#  OUTPUTS:  appended non-standard file, updated index file
#
#  Last modified on: 08/20/2015
#  Last modified by: Mike Warburton






usage(){
cat << EOF

This script adds web-scored variant data to the UDP's local database of non-standard CADD scores.

ASSUMPTIONS:
	The local CADD database is in /data/Udpdata(/Uploads)/Reference/CADD/v*.*/hg19/

INPUT:
	-v <version number>	The version number for the set of CADD scores (e.g. '1.3')
	-g <genome type>	The genome type for the set of CADD scores - default is 'hg19'
	-n <new scores>		The file containing the scores to be appended
	-u 			A flag to append to the current database in Uploads 

OUTPUT:
	A newly appended score file
	A new index file for that database file

EOF
}



# Check and collect input
if [ $# -lt 4 ] || [ $# -gt 7 ]; then
	usage
	exit 1
fi

uploadsFlag=false
while getopts "v:g:n:u" OPTION; do
	case $OPTION in
		v)
			verNum=$OPTARG;;
		g)
			genomeType=$OPTARG;;
		n)
			newFile=$OPTARG;;
		u)
			uploadsFlag=true;;
		\?)
			usage
			exit 1;;
	esac
done

if [ "$verNum" == "" ] || [ "$newFile" == "" ]; then
	usage
	exit 1
fi
if [ "$genomeType" == "" ];then
	genomeType="hg19"
fi
if [[ "$newFile" == *gz ]]; then
	gunzip -f $newFile
	newFile=${newFile%.gz}
fi


# Set variables
oDbGz="/data/Udpdata/Reference/CADD/v$verNum/$genomeType/non-standard_Variants.tsv.gz"
if $uploadsFlag; then
	oDbGz="/data/Udpdata/Uploads/Reference/CADD/v$verNum/$genomeType/non-standard_Variants.tsv.gz"
fi
oDB="/data/Udpdata/Uploads/Reference/CADD/v$verNum/$genomeType/non-standard_Variants.old.tsv"
nDB="/data/Udpdata/Uploads/Reference/CADD/v$verNum/$genomeType/non-standard_Variants.tsv"

# Unzip the non-standard CADD database into the Uploads directory
gunzip -c $oDbGz > $oDB

# Concatenate and sort the score files
echo "Combining and sorting files"
oFL=`grep -n -m1 "#CHROM" $oDB | cut -d':' -f1`
((oFL++))
nFL=`grep -n -m1 "#CHROM" $newFile | cut -d':' -f1`
((nFL++))

cat <(tail -n +$oFL $oDB) <(tail -n +$nFL $newFile) | sort -n -k 1 -k 2 -k 3 -k 4 | uniq > $nDB.temp
((oFL--))
cat <(head -$oFL $oDB) $nDB.temp > $nDB


# Zip and index the new database
echo "Zipping new file"
bgzip -f $nDB

echo "Indexing new file"
tabix -f -b 2 -e 2 ${nDB}.gz
chgrp Udpbinfo ${nDB}.gz.tbi

rm $nDB.temp
rm $oDB
echo "Finished"

