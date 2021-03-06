#!/bin/bash

#Automatic exit from bash shell script on error
set -e

usage()
{
    echo -e "SQUAT: a Sequencing Quality Assessment Tool"
    echo -e "Usage: $0 seq1 seq2 ...  seqN [-o <output_dir>] [-r <ref_asm>]\n"
    echo "Optional args:"
    echo "-t    --thread    <int>   Number of threads to use" 
    echo "-f    --flush  flush The sam file after alignment" 
    echo "-s    --subset    <str>   Return the subset of sequencing reads according to labels (in capitals, e.g. PSCO)" 
    echo "-g   <str>   Path to the reference genome file for GAGE benchmark tool" 
    echo "--gage    Activate gage mode, must specify reference genome (-g)"
    echo "--sample-size <int>    the read size for random sampling, default 1M"
    echo "--all    Deactivate random sampling, take the whole read file as input"
    echo "-c   <float>   The threshold for overall sequencing quality" 
    echo "--mt   --mismatch-thre <float>    Threshold for reads with substitution errors. Above threshold = poor quality reads, default 0.2"  
    echo "--ct   --clip-thre    <float>   Threshold for reads containing clips. Above threshold = poor quality reads, default 0.3"  
    echo "--ot   --others-thre    <float>   Threshold for reads with other errors. Above threshold = poor quality reads, default 0.1" 
    echo "--nt   --n-thre   <float>   Threshold for reads containing N. Above threshold = poor quality reads, default 0.1" 
    echo "--seed   <int>   Specify the seed for random sampling, default 0" 
}

function change_id {
    cat $2 | \
    awk -v OUT=$1 \
        -v MATCH=$(dirname "$1")/$3.ids \
    'BEGIN{
        id = 0
    }
    {
        if(NR%4==1){
            print "@"id > OUT
            print id"\t@"$0 > MATCH
            id+=1
        }
        else{
            print $0 > OUT
        }
    }
    END{
        print id
    }
    '
}


function to_abs {
    case $1 in
        /*) absolute=$1;;
        *) absolute=$PWD/$1;;
    esac
    echo $absolute
}


if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

#default parameter value
MAXPROC=$(($(grep -c ^processor /proc/cpuinfo)/3))
FLUSH_SAM=NO
NUM_SAMPLE=1000000
SUBSET=NONE
FULLSET=NO
CRITERIA=0.2
NM_THRE=0.2
CR_THRE=0.3
O_THRE=0.1
N_THRE=0.1
SEED=0

SEQ_LIST=()
NUM_SEQ=0

while true; do
    if [[ $1 != "-"* && $# -gt 0 ]];
    then
        SEQ_LIST+=($( to_abs $1 ))
        NUM_SEQ=$(($NUM_SEQ+1))
        shift #pass seq files
    else
        break
    fi
done


while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h|--help)
    usage
    exit 0
    ;;
    -f|--flush)
    FLUSH_SAM=YES
    shift
    ;;
    -o)
    OUTDIR="$( to_abs $2 )"
    shift # past argument
    shift # past value
    ;;
    -r)
    REFLOC="$( to_abs $2 )"
    shift # past argument
    shift # past value
    ;;
    -t|--thread)
    MAXPROC="$2"
    shift # past argument
    shift # past value
    ;;
    -s|--subset)
    SUBSET="$2"
    shift # past argument
    shift # past value
    ;;
    -g)
    GAGELOC="$( to_abs $2 )"
    shift # past argument
    shift # past value
    ;;
    --gage)
    GAGE=YES
    shift # past argument
    ;;
    --sample-size)
    NUM_SAMPLE=$2
    shift # past argument
    shift # past argument
    ;;
    --all)
    FULLSET=YES
    shift # past argument
    ;;
    -c)
    CRITERIA=$2
    shift # past argument
    shift # past argument
    ;;
    --mt|--mismatch-thre)
    NM_THRE=$2
    shift # past argument
    shift # past argument
    ;;
    --cr|--clip-thre)
    CR_THRE=$2
    shift # past argument
    shift # past argument
    ;;
    --ot|--others-thre)
    O_THRE=$2
    shift # past argument
    shift # past argument
    ;;
    --nt|--n-thre)
    N_THRE=$2
    shift # past argument
    shift # past argument
    ;;
    --seed)
    SEED=$2
    shift # past argument
    shift # past argument
    ;;
    *)    # unknown option
    echo "Unknown option: "$1 >&2
    exit 1
    ;;
esac
done

if [[ -z "$OUTDIR" || -z "$REFLOC" ]]; then
    usage
    exit 1
fi

EXECDIR="$( cd "$(dirname "$0")" ; pwd)"

#write config file
mkdir -p ${OUTDIR} &> /dev/null
echo "PQ%: ${CRITERIA}" > ${OUTDIR}/config
echo "MR%: ${NM_THRE}" >> ${OUTDIR}/config
echo "CR%: ${CR_THRE}" >> ${OUTDIR}/config
echo "OR%: ${O_THRE}" >> ${OUTDIR}/config
echo "NR%: ${N_THRE}" >> ${OUTDIR}/config


function do_squat {
    ORGECV="$( to_abs $1 )"
    #echo $ECVLOC
    xbase=${ORGECV##*/}
    DATA=${xbase%.*}
    SEQDIR=${OUTDIR}/${DATA}
    ECVLOC=${SEQDIR}/${DATA}.fastq
    #ECVLOC=$(dirname "$0")/${DATA}_ecv.fastq

    #delete if output dir already exists
    if [ -d ${SEQDIR} ]; then
        rm -r ${SEQDIR} &> /dev/null
    fi
    mkdir ${SEQDIR} &> /dev/null

    touch ${SEQDIR}/${DATA}.log
    echo "Start examining ${DATA}" | tee -a ${SEQDIR}/${DATA}.log

    #echo "Calculate number of reads"  | tee -a ${SEQDIR}/${DATA}.log
    if [ "$FULLSET" == "YES" ]; then
        READSIZE=$( change_id ${ECVLOC} ${ORGECV} ${DATA} )
        NUM_SAMPLE=${READSIZE}
        echo "No. of reads: ${READSIZE}" | tee -a ${SEQDIR}/${DATA}.log
    else
        READSIZE=$(($(wc -l $ORGECV | cut -d ' ' -f 1)/4))
        if [ "$NUM_SAMPLE" -gt "$READSIZE" ]; then
            NUM_SAMPLE=$( change_id ${ECVLOC} ${ORGECV} ${DATA} )
            echo "No. of reads: ${NUM_SAMPLE}" | tee -a ${SEQDIR}/${DATA}.log
        else
            echo "sampling ${NUM_SAMPLE} out of ${READSIZE} records" | tee -a  ${SEQDIR}/${DATA}.log
            python3 ${EXECDIR}/library/rand_sample.py ${ECVLOC} ${ORGECV} ${READSIZE} ${NUM_SAMPLE} ${SEED}
        fi
    fi

    #map reads to genome using alignment tools
    echo "BWA read mapping" | tee -a ${SEQDIR}/${DATA}.log
    bash ${EXECDIR}/library/run_mapping.sh ${EXECDIR} ${SEQDIR} ${DATA} ${READSIZE} ${REFLOC} ${ECVLOC} ${MAXPROC} | tee -a ${SEQDIR}/${DATA}.log

    #quast evaluation
    echo "Evaluate genome assemblies" | tee -a ${SEQDIR}/${DATA}.log
    if [[ -z "$GAGELOC" && -z "$GAGE" ]]; then
        python3 ${EXECDIR}/quast/quast.py ${REFLOC} -o ${SEQDIR}/quast --min-contig 200 -t ${MAXPROC} -s 2>&1 > /dev/null
    else
        python3 ${EXECDIR}/quast/quast.py ${REFLOC} -o ${SEQDIR}/quast --min-contig 200 -t ${MAXPROC} -s -R ${GAGELOC} --gage 2>&1 > /dev/null 
    fi

    #pre-Q report
    echo "Generate pre-assembly reports" | tee -a ${SEQDIR}/${DATA}.log
    ${EXECDIR}/library/preQ/readQdist ${ECVLOC} ${SEQDIR}/pre_report 2>&1 > /dev/null
    cp -r ${EXECDIR}/library/preQ/link ${SEQDIR}/
    
    #analysis modules
    echo "Generate post-assembly reports" | tee -a ${SEQDIR}/${DATA}.log
    if [[ "$SUBSET" != "NONE" ]]; then
        mkdir -p ${SEQDIR}/subset &> /dev/null
    fi
    mkdir -p ${SEQDIR}/images &> /dev/null
    python3 ${EXECDIR}/library/gen_report.py -o ${OUTDIR} -i ${ECVLOC} -d ${DATA} -n ${NUM_SAMPLE} -t ${READSIZE} -s ${SUBSET} -r ${REFLOC} -e ${EXECDIR} | tee -a ${SEQDIR}/${DATA}.log

    #flush sam files
    if [ "$FLUSH_SAM" == "YES" ]; then
        echo "Flushing sam files" | tee -a ${SEQDIR}/${DATA}.log
        for tool in bwa-mem bwa-backtrack; do
            rm ${SEQDIR}/${tool}/${DATA}_ecv_all.sam
        done
    fi

    echo "Compress reports into zip"
    cd ${OUTDIR}
    if [ -d ${DATA}_report.zip ]; then
        rm ${DATA}_report.zip &> /dev/null
    fi
    mkdir -p ${DATA}_report/${DATA}; cp ${DATA}.html ${DATA}_report/
    cp -r ${DATA}/*report.htm* ${DATA}/link ${DATA}_report/${DATA}/ 2>&1 > /dev/null
    zip ${DATA}_report.zip -r9 ${DATA}_report &> /dev/null
    rm -r ${DATA}_report &> /dev/null
}

for ((i=0;i<$NUM_SEQ;i++)); do
    do_squat ${SEQ_LIST[$i]}
done