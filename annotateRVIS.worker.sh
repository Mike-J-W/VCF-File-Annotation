#!/bin/bash
#
#  annotateRVIS.worker.sh
#  This script performs RVIS annotation on a VCF segment
#  INPUTS:  VCF segment, output file, RVIS database, UCSC gene table
#  OUTPUTS: annotated VCF segment
#
#  Last modified on: 09/22/15
#  Last modified by: Mike Warburton


# Check the number of arguments
if [ $# -lt 8 ] || [ $# -gt 9 ]; then
	echo -e "\nERROR: Incorrect number of arguments\n"
	exit 1
fi

# Collect the arguments
clearInfo=false
while getopts "i:o:r:g:c" OPTION; do
	case "$OPTION" in
		i)
			inputFile="$OPTARG";;
		o)
			outputFile="$OPTARG";;
		r)
			rvisScores="$OPTARG";;
		g)
			geneTable="$OPTARG";;
		c)
			clearInfo=true;;
		\?)
			echo -e "\nERROR: Unrecognized option\n"
			exit 1;;
	esac
done

# Set 2 of the main variables
outputDir=`dirname $outputFile`
inputBase=`basename $inputFile`

# Read the input file and delimit by tab to access each field individually
while read chrName pos id ref alt qual filter info format samples; do

	# Skip any header line
	if [[ $chrName == "#"* ]]; then
		continue
	fi

	# Add the 'chr' prefix to the chr number
	chrNum=${chrName#chr}
	chr="chr$chrNum"

	# Set up the file to hold the gene info from the gene table
	geneTemp=$outputDir/${inputBase}.${chr}.${pos}.genes.temp

	# Retrieve the gene names that match the chromosome and position
	tabix $geneTable ${chr}:${pos}-${pos} | cut -f 5 | sort -u | sed "s/ /_/g" > $geneTemp
	if [ ! -e $geneTemp ] || [ ! -s $geneTemp ]; then
		echo "none" > $geneTemp
	fi

	# Set up the file to hold the RVIS scores for each gene
	rvisTemp=$outputDir/${inputBase}.${chr}.${pos}.scores.temp
	[ -e $rvisTemp ] && rm $rvisTemp

	# Loop throug the list of genes and retrieve the RVIS scores
	while read gene; do

		rvisLine=`grep "^$gene\b" $rvisScores`

		if [ "$rvisLine" == "" ]; then
			echo -e 'NF\tNF' >> $rvisTemp
		else
			echo "$rvisLine" | cut -f 4,5 >> $rvisTemp
		fi
		
	done < $geneTemp

	# Update the INFO field
	if $clearInfo || [ "$info" == "" ]; then
		info="rvis="
	else
		info=${info%;}";rvis="
	fi
	while read gene score percentile; do

		info+="$gene,$score,$percentile,"
	
	done < <(paste $geneTemp $rvisTemp)
	info=${info%,};

	# Print the fields to the output file
	echo -e "$chrName\t$pos\t$id\t$ref\t$alt\t$qual\t$filter\t$info\t$format\t$samples" >> $outputFile

	rm $geneTemp
	rm $rvisTemp

done < $inputFile
