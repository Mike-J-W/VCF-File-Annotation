#!/bin/bash
#
#  Annotation_Manager.sh
#  This script sets up and launches annotation scripts for CADD, RVIS, and can be expanded to more
#  INPUTS:  VCF file to be annotated, output dir, temp dir, uploads flags
#  OUTPUTS: annotated VCF file with all previous annotations removed
# 
#  Last modified on: 09/21/15
#  Last modified by: Mike Warburton


usage(){
cat << EOF

This script sets up and launches annotation scripts for CADD and RVIS.

Annotate Mode is default mode

        -i <VCF file>		Required	The VCF file to be annotated
        -o <output dir>		Required	The directory in which to save the output
        -t <temp dir>		Optional	The directory in which to save the temporary files; the default is the output directory
        -s <number of lines>	Optional	The number of lines per part when the VCF file is split; by default the input is split into no more than 100 pieces such that each is 1000+ lines
        -w <walltime>           Optional        The Biowulf2 walltime to set per VCF piece. Quick nodes are used by default. This will tell the script to use normal nodes with the specified walltime
        -p			Optional	A flag to skip bcftools if the file already prepared with 1 variant per line and is left-normalized
        -e			Optional	A flag to erase the INFO field of the input VCF file
        -k			Optional	A flag to keep the temporary files after the script finishes
        -f <config file>	Optional	The config file with database paths to use; the default is /data/Udpwork/usr/Common/Git/VCF_scripts/Annotation/databasePaths.config

	-c	CADD Annotation
	-a		An optional flag to show all variants, even those without a CADD score in the local database, in the output VCF file (default is to only show those in the *.noCADD.vcf file)
	-r	RVIS Annotatoin
	-h	ExAC Homozygote Annotation


Database Mode is set with '-d'

	-c			CADD Database Update
	-n <new scores>		Required	The file downloaded from CADD's website with the new InDel scores

EOF
}


# Check and collect input
if [ $# -lt 4 ] || [ $# -gt 19 ]; then
	echo -e "\nERROR: Too few or too many arguments\n"
	usage
	exit 1
fi

# Set up the main variables
scriptDir=/data/Udpwork/usr/Common/Git/VCF_scripts/Annotation/
defaultConfigFile=/data/Udpwork/usr/Common/Git/VCF_scripts/Annotation/databasePaths.config
annotateMode=false
databaseMode=false
partition="quick"
walltime="2:00:00"
preppedFile=false
clearInfo=false
keepTemp=false
caddModule=false
outputAllCadd=false
rvisModule=false
exacModule=false

# Pull in the arguments from the command line
while getopts "i:o:t:s:w:pekf:carhdn:" OPTION; do
	case $OPTION in
		i)
			inputFile="$OPTARG"
			annotateMode=true;;
		o)
			outputDir="$OPTARG"
			annotateMode=true;;
		t)
			tempDir="$OPTARG"
			annotateMode=true;;
		s)
			chunkSize="$OPTARG"
			annotateMode=true;;
		w)
			walltime="$OPTARG"
			partition="norm";;
		p)
			preppedFile=true
			annotateMode=true;;
		e)
			clearInfo=true
			annotateMode=true;;
		k)
			keepTemp=true;;
		f)
			configFile="$OPTARG";;
		c)
			caddModule=true;;
		a)
			outputAllCadd=true;;
		r)
			rvisModule=true;;
		h)
			exacModule=true;;
		d)
			databaseMode=true;;
		n)
			newCADDdata="$OPTARG"
			databaseMode=true;;
		\?)
			echo -e "\nERROR: unrecognized option\n"
			usage
			exit 1;;
		:)
			echo -e "\nOption -$OPTARG requires an argument\n"
			usage
			exit 1;;
	esac
done

# Check that the arguments for at least Mode were provided
if ! $annotateMode && ! $databaseMode; then
	echo -e "\nERROR: Insufficient arguments to run either Annotate Mode or Database Mode\n"
	usage
	exit 1
fi
# Check that Annotate Mode and Database Mode were not both run
if $annotateMode && $databaseMode; then
	echo -e "\nERROR: Cannot run annotation and database update at the same time\n"
	usage
	exit 1
fi
# If a config file was not given, use the default file
if [ "$configFile" == "" ]; then
	configFile=$defaultConfigFile
fi
# Check that the config file exists
if [ ! -e $configFile ]; then
	echo -e "ERROR: the config file with database paths, $configFile, does not exist"
	usage
	exit 1
fi
# Read the config file and pull out the database paths
caddInDels=`grep "CADD InDels" $configFile | cut -f 2`				# The CADD database of InDels
caddSNVs=`grep "CADD SNVs" $configFile | cut -f 2`				# The CADD database of SNVs
caddExtras=`grep "CADD Extras" $configFile | cut -f 2`				# The local CADD database of scores calculated by CADD's website for variants not in the default databases
rvisDb=`grep "RVIS Database" $configFile | cut -f 2`				# The RVIS database of intolerance scores by gene
geneTable=`grep "UCSC Gene Table" $configFile | cut -f 2`			# The databse of UCSC gene names and their coverage regions
exacDb=`grep "ExAC Database" $configFile | cut -f 2`				# The database of ExAC scores
referenceFasta=`grep "bcftools Reference Fasta" $configFile | cut -f 2`		# The reference genome fasta file for bcftools's left-alignment

# If a walltime was given, check its format
if [ "$partition" != "quick" ]; then
	if [[ "$walltime" != [0-9]*:[0-9][0-9]:[0-9][0-9] ]]; then
		echo -e "\nERROR: The given walltime did not match the required format. Check the Biowulf User Guide.\n"
		usage
		exit 1
	fi
fi

# If Annotate Mode was run, check the inputs
if $annotateMode; then
	# Make sure an input file and an output directory were given
	if [ "$inputFile" == "" ] || [ "$outputDir" == "" ]; then
		echo -e "\nERROR: One of the required inputs is missing\n"
		usage
		exit 1
	fi
	# Make sure the input file exists
	if [ ! -e "$inputFile" ]; then
		echo -e "\nERROR: The input VCF $inputFile does not exist\n"
		usage
		exit 1
	fi
	# Make sure the output directory exists; if it doesn't, try to make it
	if [ ! -d "$outputDir" ]; then
		mkdir -p "$outputDir"
		if [ ! -d "$outputDir" ]; then
			echo -e "\nERROR: The output directory $outputDir does not exist and could not be made\n"
			usage
			exit 1
		fi
	fi
	# If the user didn't supply a directory for the temporary files, use the output directory
	if [ "$tempDir" == "" ]; then
		tempDir="$outputDir"
	# If the user gave a temp directory, check that it exists, and try to make it if i doesn't
	elif [ ! -d "$tempDir" ]; then
		mkdir -p $tempDir
		if [ ! -d "$tempDir" ]; then
			echo -e "\nERROR: The temp directory $tempDir does not exist and could not be made\n"
			usage
			exit 1
		fi
	fi
	# Check that the reference fasta file exists
	if [ ! -e $referenceFasta ]; then
		echo -e "\nERROR: The reference fasta file, $referenceFasta, does not exist\n"
		usage
		exit 1
	fi
	# Check that at least one type of annotation was chosen
	if ! $caddModule && ! $rvisModule && ! $exacModule; then
		echo -e "\nERROR: No annotation type selected\n"
		usage
		exit 1
	fi

	# Set up a variable used under multiple circumstances in Annotate Mode
	fieldsLine=`grep -n -m1 "^#CHROM" $inputFile | cut -d':' -f 1`
fi

# If Database Mode was run, check the inputs 
if $databaseMode; then
	# Make sure ExAC module wasn't set
	if $exacModule; then
		echo -e "\nERROR: ExAC databases cannot be updated with this script\n"
		usage
		exit 1
	fi
	# Make sure RVIS module wasn't set
	if $rvisModule; then
		echo -e "\nERROR: RVIS databases cannot be updated with this script\n"
		usage
		exit 1
	fi
	# If the CADD module wasn't set, there is nothing for Database Mode to do
	if ! $caddModule; then
		echo -e "\nERROR: No database type selected\n"
		usage
		exit 1
	# If the CADD module was set, check that a file of scores was provided and that the file exists
	else
		if [ "$newCADDdata" == "" ]; then
			echo -e "\nERROR: No new CADD scores provided\n"
			usage
			exit 1
		fi
		if [ ! -e "$newCADDdata" ]; then
			echo -e "\nERROR: New CADD scores file $newCADDdata does not exist\n"
			usage
			exit 1
		fi
	fi
fi
	
# Perform checks specific to the CADD module, if it was set
if $caddModule; then
	# Check that the InDel database given in the config file exists
	if [ ! -e $caddInDels ]; then
	        echo -e "\nERROR: $caddInDels does not exist\n"
		usage
	        exit 1
	fi
	# Get the last-modification time of the InDel database
	caddInDelsTime=`stat -c%Y $caddInDels`
	# Check that the index for the InDel database exists
	if [ ! -e ${caddInDels}.tbi ]; then
	        echo -e "\nERROR: the index for $caddInDels does not exist. Please make it\n"
		usage
	        exit 1
	fi
	# Get the last-modification time of the InDel database index
	caddInDelsIndexTime=`stat -c%Y ${caddInDels}.tbi`
	# Check that the InDel database has not been modified more recently than its index
	if [ $caddInDelsTime -gt $caddInDelsIndexTime ]; then
	        echo -e "\nERROR: the index for $caddInDels is out of date. Please remake it\n"
		usage
	        exit 1
	fi
	# Check that the SNV database given in the config file exists
	if [ ! -e $caddSNVs ]; then
       		echo -e "\nERROR: $caddSNVs does not exist\n"
		usage
        	exit 1
	fi	
	# Get the last-modification time of the SNV database
	caddSNVsTime=`stat -c%Y $caddSNVs`
	# Check that the index for the SNV database exists
	if [ ! -e ${caddSNVs}.tbi ]; then
	        echo -e "\nERROR: the index for $caddSNVs does not exist.  Please make it\n"
		usage
	        exit 1
	fi
	# Get the last-modification time of the SNV database index
	caddSNVsIndexTime=`stat -c%Y ${caddSNVs}.tbi`
	# Check that the SNV database has not been modified more recently than its index
	if [ $caddSNVsTime -gt $caddSNVsIndexTime ]; then
	        echo -e "\nERROR: the index $caddSNVs is out of date. Please remake it\n"
		usage
	        exit 1
	fi
	# Check that the local non-standard variant database given in the config file exists
	if [ ! -e $caddExtras ]; then
	        echo -e "\nERROR: $caddExtras does not exist\n"
		usage
	        exit 1
	fi
	# Get the last-modification time of the local non-standard variant database
	caddExtrasTime=`stat -c%Y $caddExtras`
	# Check that the index for the local non-standard variant database exists
	if [ ! -e ${caddExtras}.tbi ]; then
	        echo -e "\nERROR: the index for $caddExtras does not exist. Please make it\n"
		usage
	        exit 1
	fi
	# Get the last-modification time of the local non-standard variant database index
	caddExtrasIndexTime=`stat -c%Y ${caddExtras}.tbi`
	# Check that the local non-standard variant database has not been modified more recently than its index
	if [ $caddExtrasTime -gt $caddExtrasIndexTime ]; then
	        echo -e "\nERROR: the index for $caddExtras is out of date. Please remake it\n"
		usage
	        exit 1
	fi

	realCaddSNVs=`readlink -f $caddSNVs`		# Get the target of the CADD SNV database soft link
	caddDir=`dirname $realCaddSNVs`			# Get the CADD directory
	caddGenome=`basename $caddDir`			# Get the genome of the CADD version
	caddVersion=`basename $(dirname $caddDir)`	# Get the CADD version

elif $outputAllCadd; then

	echo -e "\nERROR: -a (output all variants, even ones missing CADD scores) was set without -c (add CADD annotation) also being set.\n"
	usage
	exit 1

fi

# Perform checks specific to the RVIS module, if it was set
if $rvisModule; then
	# Check that the RVIS database exists
	if [ ! -e $rvisDb ]; then
		echo -e "\nERROR: $rvisDb does not exist\n"
		usage
		exit 1
	fi
	# Check that the UCSC gene table exists
	if [ ! -e $geneTable ]; then
	        echo -e "\nERROR: $geneTable does not exist\n"
	        usage
	        exit 1
	fi
	# Get the last-modification time of the UCSC gene table
	geneTableTime=`stat -c%Y $geneTable`
	# Check that the index for the UCSC gene table exists
	if [ ! -e ${geneTable}.tbi ]; then
	        echo -e "\nERROR: the index for $geneTable does not exist. Please make it\n"
		usage
	        exit 1
	fi
	# Check that the UCSC gene table has not been modified more recently than its index
	geneTableIndexTime=`stat -c%Y ${geneTable}.tbi`
	if [ $geneTableTime -gt $geneTableIndexTime ]; then
	        echo -e "\nERROR: the index for $geneTable is out of date. Please remake it\n"
		usage
	        exit 1
	fi

	realRvisDb=`readlink -f $rvisDb`			# Get the target of the RVIS database soft link
	rvisRelease=`basename $(dirname $realRvisDb)`		# Get the RVIS release number
	realGeneTable=`readlink -f $geneTable`			# Get the target of the UCSC gene table soft link
	geneTableGenome=`basename $(dirname $realGeneTable)`	# Get the genome of the UCSC gene table

fi

# Perform checks specific to the ExAC module, if it was run
if $exacModule; then
	# Check that the ExAC database exists
	if [ ! -e $exacDb ]; then
		echo -e "\nERROR: $exacDb does not exist\n"
		usage
		exit 1
	fi
	# Get the last-modified time of the ExAC database
	exacDbTime=`stat -c%Y $exacDb`
	# Check that the index for the ExAC database exists
	if [ ! -e ${exacDb}.tbi ]; then
		echo -e "\nERROR: the index for $exacDb does not exist. Please make it\n"
		usage
		exit 1
	fi
	# Get the last-modified time of the ExAC database index
	exacDbIndexTime=`stat -c%Y ${exacDb}.tbi`
	# Check that the ExAC database has not been modified more recently than it index
	if [ $exacDbTime -gt $exacDbIndexTime ]; then
		echo -e "\nERROR: the index for $exacDb is out of date. Please remake it\n"
		usage
		exit 1
	fi

	realExacDb=`readlink -f $exacDb`				# Get the target of the ExAC database soft link
	exacRelease=`basename $(dirname $realExacDb)`			# Get the ExAC release number
	exacRefFile=`gunzip -c $exacDb | grep -m1 "^##reference=file:"`	# Get the reference genome file used in the creation of the ExAC database
	# Check that the reference genome file was the hg19 fasta file
	if [ "$exacRefFile" == "##reference=file:///seq/references/Homo_sapiens_assembly19/v1/Homo_sapiens_assembly19.fasta" ]; then
		exacGenome="hg19"
	else
		echo -e "\nERROR: did not recognize reference file ($exacRefFile) in ExAC database $exacDb. Please use a different ExAC database or update this script\n"
		usage
		exit 1
	fi

fi

# Check that script is not being run on Helix
onHelix=false
if [ $HOSTNAME == "helix.nih.gov" ]; then
	onHelix=true
fi
if $onHelix && $annotateMode; then
	echo -e "\nERROR: Annotate Mode must be run on from Biowulf2\n"
	usage
	exit 1
fi

# Check that if user claimed that the input file was already prepped, that it does not contain a line with more than one variant
if $preppedFile; then
	multiVariants=`tail -n +$fieldsLine $inputFile | cut -f4,5 | grep ","`
	if [ "$multiVariants" != "" ]; then
		echo -e "\nERROR: The '-p' flag was used with a file that has more than one variant per line\n"
		usage
		exit 1
	fi
fi


# Run Annotation Mode
if $annotateMode; then

        # Create the variables for bcftools and the annotate script
        inputBase=`basename $inputFile`
        inputBaseStem=${inputBase%.vcf}

	# Set the file to hold the header of the VCF file
	header=$tempDir/${inputBaseStem}.header.vcf
	# Pull the header from the input VCF file
	((fieldsLine--))
	head -$fieldsLine $inputFile | grep -v "^##INFO=<ID" > $header

	# If the CADD module was set, print the CADD annotation definitons to the header
	if $caddModule; then
		echo "##INFO=<ID=cadd_raw,Number=1,Type=Float,Description=\"The raw CADD score for the variant. From CADD ${caddVersion}, $caddGenome\">" >> $header
		echo "##INFO=<ID=cadd_phred,Number=1,Type=Float,Description=\"The Phred-scaled CADD score for the variant. From CADD ${caddVersion}, $caddGenome\">" >> $header
	fi
	# If the RVIS module was set, print the RVIS annotation definition to the header
	if $rvisModule; then
		echo "##INFO=<ID=rvis,Number=.,Type=String,Description=\"The 0.01% RVIS score and its percentile for the gene(s) of the variant. From RVIS ${rvisRelease}, $geneTableGenome\">" >> $header
	fi
	# If the ExAC module was set, print the ExAC annotation definition to the header
	if $exacModule; then
		echo "##INFO=<ID=exac_AC_hom,Number=1,Type=Float,Description=\"The ExAC homozygote allele count. From ExAC ${exacRelease}, ${exacGenome}\">" >> $header
	fi

	# Pull the '#CHROM...' line from the input VCF file and append it to the header
	((fieldsLine++))
	head -$fieldsLine $inputFile | tail -1 >> $header

	# Set the file to become the VCF file to be annotated
	annotationInput=$tempDir/${inputBaseStem}.annotationPrepped.vcf
	
	# If the input VCF file was not prepped, use bcftools to split and left-align it
	if ! $preppedFile; then
		# Set the files to hold the temporary versions of the input as it's processed
		cleanFORMATvcf=$tempDir/${inputBaseStem}.pgt_pid_removed.vcf
	        splitVCF=$tempDir/${inputBaseStem}.splitVariants.vcf
	        strippedVCF=$tempDir/${inputBaseStem}.infoStripped.vcf
		newBody=$tempDir/${inputBaseStem}.newBody.vcf
	
		# Remove PGT and PID FORMAT fields from any lines that have them
		#py

	        # Strip the INFO fields
	        [ -e $newBody ] && rm $newBody
	        echo "Stripping the INFO fields"
		awk 'BEGIN {FS="\t"; OFS="\t"} ($1 !~ "\#.*") {$8="."; print $0}' $inputFile > $newBody
		# Combine the header with the info-stripped body
	        cat $header $newBody > $strippedVCF
	        rm $header
	        rm $newBody
			
	        module load samtools/1.2
		
		echo "Running bcftools to prepare VCF file for annotation"
	        # Run bcftools to split lines in the VCF file so that there is one variant per line
	        bcftools norm -m-both -o $splitVCF $strippedVCF
	        if [ $? != "0" ]; then
	                echo -e "\nERROR: bcftools failed while trying to split the variants in $strippedVCF\n"
	                exit 1
	        fi
	
	        # Run bcftools to left-align the REF/ALT sequences on each line
	        bcftools norm -f "$referenceFasta" -o "$annotationInput" "$splitVCF"
	        if [ $? != "0" ]; then
	                echo -e "\nERROR: bcftools failed while trying to left-normalize the sequence positions in $splitVCF\n"
	                exit 1
	        fi

		# If the user doesn't want to keep the temporary files, remove them
		if ! $keepTemp; then
			rm $strippedVCF
			rm $splitVCF
		fi
		
	# If the input VCF file was prepped, combine the appended header with the body
	else
		((fieldsLine++))
		vcfBody=$tempDir/${inputBaseStem}.bodyOnly.vcf
		tail -n +$fieldsLine $inputFile > $vcfBody
		((fieldsLine--))
		cat $header $vcfBody > $annotationInput
	fi

	
	echo "Splitting VCF file into parts"
	# Set the variables to be used in creating new filenames
	annotationBase=`basename $annotationInput`
	annotationBaseStem=${annotationBase%.vcf}
	annotationPart=$tempDir/${annotationBaseStem}.part

	# Split the body of the VCF file to be annotation into parts
	fieldsLine=`grep -n -m1 "^#CHROM" $annotationInput | cut -d':' -f1`
	((fieldsLine++))
	# If the user did not specify a size, set the chunk size so that no more than 100 pieces, each at least 1,000 lines, are created
	if [ "$chunkSize" == "" ]; then
		lineCount=`tail -n +$fieldsLine $annotationInput | wc -l`
		chunkSize=${lineCount%??}
		((chunkSize++))
		if [ $chunkSize -lt 1000 ]; then
			chunkSize=1000
		fi
	fi
	split -a4 -l $chunkSize <(tail -n +$fieldsLine $annotationInput) $annotationPart
	((fieldsLine--))

	# Set the name of the output VCF file
	successFile=$outputDir/$annotationBaseStem.
	if $caddModule; then		# If the CADD module was set, include it in the name
		successFile+="CADD_"
	fi
	if $rvisModule; then		# Same for the RVIS module
		successFile+="RVIS_"
	fi
	if $exacModule; then		# Same for the ExAC module
		successFile+="ExAC_"
	fi
	successFile+="annotated.vcf"

	echo "Submitting Biowulf2 annotation jobs for each part of VCF file"
	# Loop through pieces of the annotation-ready input VCF file
	for file in ${annotationPart}*; do
		# Set up the variables used between annotation modules
		partID=${file##*.}
		fileForModule=$file
		caddJob=${file%.part*}.caddJob.$partID
		rvisJob=${file%.part*}.rvisJob.$partID
		exacJob=${file%.part*}.exacJob.$partID
		
		# If the CADD module was set, create an sbatch file and job for it
		if $caddModule; then
			
			fileForModuleOut=${fileForModule%.part*}.withCADD.$partID	# The output file for the CADD annotation on this piece
			fileForModuleCaddFail=${fileForModule%.part*}.noCADD.$partID	# The output file for the unsuccessful CADD annotations on this piece
			caddCMD=${file%.part*}.caddModuleCMD.$partID			# The file to hold the commands submitted to Biowulf2
			echo "#!/bin/bash" > $caddCMD								# Set the language
			echo "#SBATCH --job-name=CADD$partID" >> $caddCMD					# Set the job ID
			echo "if [ ! -e $fileForModule ]; then" >> $caddCMD					# Check that the input file exists
			echo -e "\techo \"ERROR: CADD input, $fileForModule, does not exist\"" >> $caddCMD	#   Print an error if it doesn't
			echo -e "\texit 1" >> $caddCMD								#   Then quit the job
			echo "fi" >> $caddCMD
			# Execute the CADD annotation worker scrit, feeding the file to annotate, the output file, the failed output file, and the reference databases
			echo -n "$scriptDir/annotateCADD.worker.sh -i $fileForModule -o $fileForModuleOut -f $fileForModuleCaddFail -s $caddSNVs -d $caddInDels -e $caddExtras" >> $caddCMD
			if ! $preppedFile && $clearInfo; then		# If the file wasn't prepped and user wants to erase the INFO fields, set the flag for that
				echo -n " -c" >> $caddCMD
			fi
			if $outputAllCadd; then				# If the user wants every variant in the output file, set the flag for that
				echo -n " -a" >> $caddCMD
			fi
			echo "" >> $caddCMD
			if ! $keepTemp; then				# If the user doesn't want to keep the temporary files, include commands to delete:
				echo "rm $fileForModule" >> $caddCMD	#   the input file to the worker script
				echo "rm $caddCMD" >> $caddCMD		#   the command script itself
			fi
			
			# Submit the launch commands for the CADD annotation to Biowulf2, saving the output and error streams to file, and using a 'quick' partition
			sbatch --error=$tempDir/${annotationBaseStem}.CADD.${partID}.err --output=$tempDir/${annotationBaseStem}.CADD.${partID}.out --partition=$partition --time=$walltime $caddCMD > $caddJob

			# Set the input file for the next module as the output file of this module
			fileForModule=$fileForModuleOut
		fi

		# If the RVIS module was set, create an sbatch file and job for it
		if $rvisModule; then
			
			fileForModuleOut=${fileForModule%.part*}.withRVIS.$partID	# The output file for the RVIS annotation on this piece
			rvisCMD=${file%.part*}.rvisModuleCMD.$partID			# The file to hold the commands submitted to Biowulf2
			echo "#!/bin/bash" > $rvisCMD								# Set the language
			echo "#SBATCH --job-name=RVIS$partID" >> $rvisCMD					# Set the job ID
			echo "if [ ! -e $fileForModule ]; then" >> $rvisCMD					# Check that the input file exists
			echo -e "\techo \"ERROR: RVIS input, $fileForModule, does not exist\"" >> $rvisCMD	#   Print an error if it doesn't
			echo -e "\texit 1" >> $rvisCMD								#   Then quit the job
			echo "fi" >> $rvisCMD
			# Execute the RVIS annotation worker script, feeding the file to annotate, the output file, the RVIS database, and the UCSC gene table
			echo -n "$scriptDir/annotateRVIS.worker.sh -i $fileForModule -o $fileForModuleOut -r $rvisDb -g $geneTable" >> $rvisCMD
			# If the file wasn't prepped, the CADD module wasn't set, and the user wants to erase the INFO fields, set the flag for that
			if ! $preppedFile && ! $caddModule && $clearInfo; then
				echo -n " -c" >> $rvisCMD
			fi
			echo "" >> $rvisCMD
			if ! $keepTemp; then				# If the user doesn't want to keep the temporary files, include commands to delete:
				echo "rm $fileForModule" >> $rvisCMD	#   the input file to the worker script
				echo "rm $rvisCMD" >> $rvisCMD		#   the command script itself
			fi

			# Submit the launch commands for the RVIS annotation to Biowulf2, saving the output and error streams to file, and using a 'quick' partition
			# If a CADD job was run for this piece, get the job ID for that annotation and set this module to be dependent on that one
			if [ -e "$caddJob" ]; then
				caddJobID=`cat $caddJob`
				if ! $keepTemp; then
					rm $caddJob
				fi
				sbatch --error=$tempDir/${annotationBaseStem}.RVIS.${partID}.err --output=$tempDir/${annotationBaseStem}.RVIS.${partID}.out --partition=$partition --time=$walltime --dependency=afterany:$caddJobID $rvisCMD >> $rvisJob
			else
				sbatch --error=$tempDir/${annotationBaseStem}.RVIS.${partID}.err --output=$tempDir/${annotationBaseStem}.RVIS.${partID}.out --partition=$partition --time=$walltime $rvisCMD >> $rvisJob
			fi
			
			# Set the input file for the next module as the output file of this module
			fileForModule=$fileForModuleOut
			
		fi
		
		# If the ExAC module was set, create an sbatch file and job for it
		if $exacModule; then
			
			fileForModuleOut=${fileForModule%.part*}.withExAC.$partID	# The output file for the ExAC annotation on this piece
			exacCMD=${file%.part*}.exacModuleCMD.$partID			# The file to hold the commands submitted to Biowulf2
			echo "#!/bin/bash" > $exacCMD								# Set the language
			echo "#SBATCH --job-name=ExAC$partID" >> $exacCMD					# Set the job ID
			echo "if [ ! -e $fileForModule ]; then" >> $exacCMD					# Check that the input file exists
			echo -e "\techo \"ERROR: ExAC input, $fileForModule, does not exist\"" >> $exacCMD	#   Print an error if it doesn't
			echo -e "\texit 1" >> $exacCMD								#   Then quit the job
			echo "fi" >> $exacCMD
			# Execute the ExAC annotation worker script, feeding the file to annotate, the output file, and the ExAC database
			echo -n "$scriptDir/annotateExAC.worker.sh -i $fileForModule -o $fileForModuleOut -d $exacDb" >> $exacCMD
			# If the input VCF file wasn't prepped, no other module was set, and the user wants to erase the INFO fields, set the flag for that
			if ! $preppedFile && ! $caddModule && ! $rvisModule && $clearInfo; then
				echo -n " -c" >> $exacCMD
			fi
			echo "" >> $exacCMD
			if ! $keepTemp; then				# If the user doesn't want to keep the temporary files, include commands to delete:
				echo "rm $fileForModule" >> $exacCMD	#   the input file to the worker script
				echo "rm $exacCMD" >> $exacCMD		#   the command scrit itself
			fi

			# Submit the launch commands for the ExAC annotation to Biowulf2, saving the output and error streams to file, and using a 'quick' partition
			# If a RVIS job was run for this piece, get the job ID for that annotation and set this module to be dependent on that one
			if [ -e "$rvisJob" ]; then
				rvisJobID=`cat $rvisJob`
				if ! $keepTemp; then
					rm $rvisJob
				fi
				sbatch --error=$tempDir/${annotationBaseStem}.ExAC.${partID}.err --output=$tempDir/${annotationBaseStem}.ExAC.${partID}.out --partition=$partition --time=$walltime --dependency=afterany:$rvisJobID $exacCMD >> $exacJob
			# If not a RVIS but a CADD job was run for this piece, use the job ID to set this module to be dependent on that one
			elif [ -e "$caddJob" ]; then
				caddJobID=`cat $caddJob`
				if ! $keepTemp; then
					rm $caddJob
				fi
				sbatch --error=$tempDir/${annotationBaseStem}.ExAC.${partID}.err --output=$tempDir/${annotationBaseStem}.ExAC.${partID}.out --partition=$partition --time=$walltime --dependency=afterany:$caddJobID $exacCMD >> $exacJob
			else
				sbatch --error=$tempDir/${annotationBaseStem}.ExAC.${partID}.err --output=$tempDir/${annotationBaseStem}.ExAC.${partID}.out --partition=$partition --time=$walltime $exacCMD >> $exacJob
			fi

			# Set the input file for the next module as the output file of this module
			fileForModule=$fileForModuleOut
			
		fi

	done

	# Combine the annotation files
	allJobs=$tempDir/${inputBase}.allJobs				# Set the file name to contain the job IDs for all the annotation jobs
	cat ${annotationPart%.part*}.*Job.part* > $allJobs		# Print all the job IDs to the file
	jobIDs=`tr '\n' ',' < $allJobs`					# Change the list from line-separated to comma-delimited
	jobIDs=${jobIDs%,}						# Remove the trailing comma
	concatCMD=$tempDir/${annotationBaseStem}.collectAll.cmd		# Set the file to hold the concatenation and clean-up commands
	echo "#!/bin/bash" > $concatCMD					# Set the language
	echo "#SBATCH --job-name=ConcatParts" >> $concatCMD		# Set the job ID
	# Concatenate the header of the annotation-input file and all the final annotated pieces of the body of the input VCF file
	echo "cat <(head -$fieldsLine $annotationInput) ${fileForModule%.part*}* > $successFile" >> $concatCMD
	# If the CADD module was set, also concatenate the failed output file from the CADD annotation
	if $caddModule; then
		echo "cat <(head -$fieldsLine $annotationInput) ${fileForModuleCaddFail%.part*}* > $outputDir/${annotationBaseStem}.noCADD.vcf" >> $concatCMD
		# If the user doesn't want to keep the temporary files, remove all the failed CADD pieces
		if ! $keepTemp; then
			echo "rm ${fileForModuleCaddFail%.part*}.part*" >> $concatCMD
		fi
	fi
	# If the user doesn't want to keep the temporary files, include commnads to remove them
	if ! $keepTemp; then
		echo "rm $annotationInput" >> $concatCMD
		# Create a loop to catch all the sbatch output & error files that aren't empty and save them
		echo "for file in $tempDir/${annotationBaseStem}*part*err $tempDir/${annotationBaseStem}*part*out; do" >> $concatCMD
		echo "    if [ -s \"\$file\" ]; then" >> $concatCMD
		echo "        newFile=\$(echo \"\$file\" | sed s/\\.part/./)" >> $concatCMD
		echo "        mv \$file \$newFile" >> $concatCMD
		echo "    fi" >> $concatCMD
		echo "done" >> $concatCMD
		echo "rm ${annotationPart%.part*}.*.part*" >> $concatCMD
		echo "rm $allJobs" >> $concatCMD
		echo "rm $concatCMD" >> $concatCMD
	fi

	# Submit the lauch commands for the concatenation script, saving the output and error streams to file, using a 'quick' partition, and making it dependent on all the annotation jobs
	sbatch --error=$tempDir/${annotationBaseStem}.ConcatParts.err --output=$tempDir/${annotationBaseStem}.ConcatParts.out --partition=quick --dependency=afterany:$jobIDs $concatCMD

	echo "This script is finished, but the annotation jobs most likely are not. Check your jobload for further information."

fi


# Run Database Mode
if $databaseMode; then

	if $caddModule; then
		updateCaddCMD="$scriptDir/append_non-standard-CADD.sh -v $caddVersion -g $caddGenome -n $newCADDdata"
		if $caddUploads; then
			updateCaddCMD+=" -u"
		fi

		$updateCaddCMD
	fi
fi
