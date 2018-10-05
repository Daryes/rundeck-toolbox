#!/bin/bash
# -------------------------------------------------------------------------------------------
# script de verification de l'etat d'executions
#
# aide integree
# -------------------------------------------------------------------------------------------
# 2018/04/13    AHZ creation
# 2018/08/23    AHZ affichage detaille des erreurs API
#

# external environment variables
# RD_TOKEN=<from user env variable>
# RD_JOB_SERVERURL=<from user env or rundeck>

# Rundeck API request allowed job status
# source : http://rundeck.org/docs/api/index.html#execution-query
RUND_JOB_STATUS_LIST="running succeeded failed aborted"

# default values
TARGET_PROJECT_NAME="all"
TARGET_GROUP_NAME=""
TARGET_JOB_NAME=""
TARGET_JOB_ID=""

# CURL syntax
CURL_API_ROOT="${RD_JOB_SERVERURL%/}/api"
CURL_API_CMD="curl --silent --get --data-urlencode authtoken=${RD_TOKEN} ${CURL_API_ROOT}"

OUTPUT_VERBOSE=0
OUTPUT_STYLE=""

# ----------------------------------------------------------------------------
# syntax
function usageSyntax() {
    echo -e "
syntaxe    : $(basename $0) [-project '<rundeck project>' [ -group '<jobs group>' -job '<job name>' ] ] [ -format influx ] [ -verbose ]

 -project: a name or 'all' (default if absent)
If -group and -job are present, 'all' cannot be used.

 "
}

# ----------------------------------------------------------------------------
# stderr output
echoerr() { printf "%s\n" "$*" >&2; }

# find a job GID from his project, group and job names
rdJob_GetIdFromName() {    
    CURL_API_VERSION=17
    sData=$( ${CURL_API_CMD}/${CURL_API_VERSION}/project/${TARGET_PROJECT_NAME}/jobs --data-urlencode groupPathExact="$TARGET_GROUP_NAME" --data-urlencode jobExactFilter="$TARGET_JOB_NAME"  )
    if [ $? -ne 0 ] || ! echo "$sData"|grep -i -q "<jobs count="; then echoerr "Error: rdJob_GetIdFromName - bad API query"; echoerr "$sData"; exit 1; fi
    if echo "$sData"|grep -i -q "<jobs count='0'"; then echoerr "Error: rdJob_GetIdFromName - job '$TARGET_JOB_NAME' does not exist"; echoerr "$sData"; exit 1; fi
    if ! echo "$sData"|grep -i -q "<jobs count='1'>"; then echoerr "Error: rdJob_GetIdFromName - more than a single job was returned "; echoerr "$sData"; exit 1; fi
        
    # format attendu : <job id='a4997c82-86b9-42fb-8bfd-ff57fad90202' href='http://...' ...>
    echo "$sData" | grep -oP -i "job id='\K.*?(?=')"
}


rdJob_GetLastExecData() {
    CURL_API_VERSION=1
    sData=$( ${CURL_API_CMD}/${CURL_API_VERSION}/job/${TARGET_JOB_ID}/executions --data-urlencode max=1 )    
    if [ $? -ne 0 ]; then echoerr "Error: rdJob_GetLastExecData - bad API query"; echoerr "$sData"; exit 1; fi

    echo "$sData" | grep -v '^#'
    return 0    # grep renvoie rc=1 s'il n'y a pas de donnees
}

# ----------------------------------------------------------------------------


# test d'acces a l'API via curl
sTemp=$( ${CURL_API_CMD}/1/projects 2>&1)
if [ $? -ne 0 ] || ! echo "$sTemp" | grep -i -q "projects count="; then echoerr "Error: cannot contact Rundeck API"; echoerr "$sTemp"; exit 1; fi


# verification de la presence de parametres
if [ $# -eq 0 ]; then usageSyntax; exit 1; fi

# traitement de la ligne de commande
while [ $# -gt 0 ]; do 
    arg="$1"

    case $arg in
        -project)
            TARGET_PROJECT_NAME="$2"
            [ "$TARGET_PROJECT_NAME" == "*" ] && TARGET_PROJECT_NAME="all"
            shift
            ;;

        -group)
            TARGET_GROUP_NAME="$2"
            shift
            ;;

        -job)
            TARGET_JOB_NAME="$2"
            shift
            ;;
            
        -format|-output|-style)
            OUTPUT_STYLE="$2"
            [ "$OUTPUT_STYLE" == "influxdb" ] && OUTPUT_STYLE="influx"
            
            shift
            ;;
            
        -verbose)
            OUTPUT_VERBOSE=1
            ;;
            
        *)
            # rundeck can pass additionals spaces as args
            if [ ! -z "$( echo $1 | tr -d '[:space:]' )" ]; then
                echoerr "Error: '$1' argument is unknown"
                usageSyntax
                exit 1
            fi
            ;;
    esac
    
    #  argument suivant
    [ $# -gt 0 ] && shift
done

if [ ! -z "$TARGET_GROUP_NAME" ] && [ -z "$TARGET_JOB_NAME" ]; then echo "Error: a job name is required when -group is used"; exit 1; fi
if [ -z "$TARGET_GROUP_NAME" ] && [ ! -z "$TARGET_JOB_NAME" ]; then echo "Error: a group name is required when -job is used"; exit 1; fi
if [ "$TARGET_PROJECT_NAME" == "all" ] && [ ! -z "$TARGET_JOB_NAME" ]; then echo "Error: the project name cannot be 'all' or '*' when a job name is used"; exit 1; fi


# information banner
if [ $OUTPUT_VERBOSE -eq 1 ]; then
    echo "RUNDECK job status"
    echo "Command line used : $0 $*"
    echo ""
    echo "Current PID:$$"
    echo "----------------------------------------------"
    echo "PROJECT:    $TARGET_PROJECT_NAME"
    echo "GROUP:      $TARGET_GROUP_NAME"
    echo "JOB NAME:   $TARGET_JOB_NAME"
    echo "----------------------------------------------"
    echo ""
fi

RUND_PROJECTS="$TARGET_PROJECT_NAME"

# retrieving the projects list
CURL_API_VERSION=1
RUND_PROJECTS_LIST=$( ${CURL_API_CMD}/${CURL_API_VERSION}/projects )
if [ $? -ne 0 ]; then echoerr "Error: projects list - bad API query"; echoerr "$RUND_PROJECTS_LIST"; exit 1; fi

RUND_PROJECTS_LIST=$( echo "${RUND_PROJECTS_LIST}" | grep -Po "<name>\K.*?(?=</name>)" )

if [ "$TARGET_PROJECT_NAME" == "all" ]; then
    RUND_PROJECTS="$RUND_PROJECTS_LIST"
else
    if ! echo "${RUND_PROJECTS_LIST}" | grep -q "$TARGET_PROJECT_NAME"; then echo "Error: the project '$TARGET_PROJECT_NAME' is unknown"; exit 1; fi
fi

# parsing RUND_PROJECTS
while read -r sCurrentProject; do

    # all projects or no specific jobname => retrieve all executions statuses
    if [ "$TARGET_PROJECT_NAME" == "all" ] || [ -z "$TARGET_JOB_NAME" ]; then
        for sCurrentStatus in $RUND_JOB_STATUS_LIST; do            
            CURL_API_VERSION=14
            sCurrentProject_AllExecStatus=$( $CURL_API_CMD/$CURL_API_VERSION/project/${sCurrentProject}/executions --data-urlencode statusFilter="$sCurrentStatus" )
            if [ $? -ne 0 ]; then echoerr "Error: execution listing on statusFilter - bad API query"; echoerr "$sCurrentProject_AllExecStatus"; exit 1; fi
    
            # Format:
            #  <executions count='0' total='0' offset='0' max='20' />
            #  <executions count='20' total='21' offset='0' max='20'> \n ... \n </executions>
            sCurrentCount=$( echo "$sCurrentProject_AllExecStatus" | head -1 | grep -Po "<executions .* total='\K.*?(?=' )" )
            
            OUTPUT_PREFIX="${sCurrentStatus}="
            [ "$OUTPUT_STYLE" == "influx" ] && OUTPUT_PREFIX="rundeck,project=${sCurrentProject},status=${sCurrentStatus} executions="
            echo "${OUTPUT_PREFIX}${sCurrentCount}"
        done
    
    # targeted project group/job
    else
        
        # recherche de l'id du job cible
        TARGET_JOB_ID=$( rdJob_GetIdFromName ) || exit 1
        if [ $OUTPUT_VERBOSE -eq 1 ]; then
            echo "JOB ID found: $TARGET_JOB_ID"
            echo ""
        fi

        # recuperation des donnees de la derniere execution, si disponibles
        TARGET_JOB_LASTEXEC_DATA=$( rdJob_GetLastExecData ) || exit 1
        if [ -z "$TARGET_JOB_LASTEXEC_DATA" ]; then
            echo "status=no execution data"
            exit 0
        fi
        
        # extract job execution status
        valueRet=$( echo "$TARGET_JOB_LASTEXEC_DATA" | grep -oP -i "<execution id=.* status='\K.*?(?=')" )
    
        OUTPUT_PREFIX="status="
        [ "$OUTPUT_STYLE" == "influx" ] && OUTPUT_PREFIX="rundeck, project=${sCurrentProject},group=${TARGET_GROUP_NAME},job=${TARGET_JOB_NAME},status=${valueRet} executions=1" && valueRet=""
        echo "${OUTPUT_PREFIX}${valueRet}"
    fi

done <<< "$RUND_PROJECTS"