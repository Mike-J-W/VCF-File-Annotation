#!/usr/local/Python/2.7.8/bin
#
#  annotateExAC.extracter.py
#  This script pulls the annotation info from a ExAC entry
#  INPUTS:  file with single ExAC entry
#  OUTPUTS: file with homozygote info for each variant in that ExAC entry
#
#  last modified on: 09/21/15
#  last modified by: Mike Warburton


import sys, re

if len(sys.argv) != 5:
	print("\nERROR: Incorrect number of arguments\n")
	sys.exit(1)


outputFileName = sys.argv[1]
refSeq = sys.argv[2]
altSeqs = sys.argv[3].split(',')
annos = sys.argv[4]

with open(outputFileName, 'w') as outputFile:

	homozygACs = re.search(r"AC_Hom=(\d+(,\d+)*)", annos)
	if homozygACs is not None:
		homozygAClist = homozygACs.group(1).split(',')
		if len(altSeqs) != len(homozygAClist):
			print("\nERROR: The number of allele counts in the ExAC homozygote annotation does not match the number of variants\n")
			sys.exit(1)
				
		for i, alt in enumerate(altSeqs):
			ref = refSeq
			while ref[-1] == alt[-1] and len(ref) > 1 and len(alt) > 1:
				ref = ref[:-1]
				alt = alt[:-1]
	
			outputFile.write("\t".join([ref, alt, homozygAClist[i]]) + '\n')
	else:
		print("\nERROR: The AC_hom annotation was not found in the ExAC database for the position\n")

