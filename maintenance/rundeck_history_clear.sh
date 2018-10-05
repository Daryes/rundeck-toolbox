#!/bin/bash
# -------------------------------------------------------------------------------------------
# script de nettoyage de l'historique d'execution de rundeck
#
# aide integree
# -------------------------------------------------------------------------------------------
# 2017/08/17    AHZ creation
# 2018/03/07    AHZ utilisation de l'API au lieu de rd-cli
# 2018/08/23    AHZ affichage detaille des erreurs API
# 2018/09/21	AHZ self-help translated to english
#

# external environment variables required
# RD_TOKEN=<from user env variable>
# RD_JOB_SERVERURL=<from user env or rundeck>

RUND_HISTORY_KEEP_VALUE=5
RUND_JOB_STATUS="succeeded"
RUND_HISTORY_TARGET="job"
RUND_HISTORY_OLDER=""
RUND_PROJECTS=""
RUND_SLEEP_DURATION_SEC=1

CURL_API_ROOT="${RD_JOB_SERVERURL%/}/api"
CURL_API_CMD="curl --silent --get --data-urlencode authtoken=${RD_TOKEN} ${CURL_API_ROOT}"
CURL_API_CMD_POST="curl --silent --data-urlencode authtoken=${RD_TOKEN} -X POST ${CURL_API_ROOT}"

# ----------------------------------------------------------------------------
# syntax
function usageSyntax() {
        echo -e "
syntax : $(basename $0) -clear < jobs | projects > [ -keep_count <nb executions> ]  [ -older <duration> ]
                  [ -state <all|running|succeeded|failed|aborted> ]
                  [ -sleep <seconds> ]

 -sleep      : increase the pause duration (in sec) between each call, in case of heavy load on the instance.
 -clear      : specify the behavior for the history cleaning : jobs or projects

 -keep_count : number of remaining execution kept for each job. No effect when used with 'projects'. Default value : $RUND_HISTORY_KEEP_VALUE
 -state      : expected execution state. Default value : $RUND_JOB_STATUS
 -older      : delete execution older than the specified value. Ex : '3m' (3 months). Best suited with 'projects'.
               Use the letter as is : h,n,s,d,w,m,y (hour,minute,second,day,week,month,year)

"
}

# stderr print function
echoerr() { printf "%s\n" "$*" >&2; }

# ----------------------------------------------------------------------------
echo "RUNDECK EXECUTION HISTORY CLEANER"
echo ""
echo "Command line used : $0 $*"
echo ""


# check parameters count
if [ $# -eq 0 ]; then usageSyntax; exit 1; fi


# parsing command line
while [ $# -gt 0 ]; do
        arg="$1"

        case $arg in
                -keep_count|-keep_history?*)
                        RUND_HISTORY_KEEP_VALUE="$2"
                        shift
                        ;;

                -state)
                        RUND_JOB_STATUS=$( echo "$2" | tr '[:upper:]' '[:lower:]' )
                        shift
                        ;;

                -older)
                        RUND_HISTORY_OLDER="--data-urlencode olderFilter=$2"
                        shift
                        ;;

                -clean|-clear)
                        RUND_HISTORY_TARGET=$( echo "$2" | tr '[:upper:]' '[:lower:]' )
                        if ! echo ";jobs;projects;" |grep -q ";${RUND_HISTORY_TARGET};"; then echo "Error : unexpected value for $arg"; exit 1; fi
                        shift
                        ;;

                -sleep)
                        RUND_SLEEP_DURATION_SEC=$2
                        shift
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

        # next arg
        [ $# -gt 0 ] && shift
done

if [ "$RUND_HISTORY_TARGET" == "projects" ] && [ -z "$RUND_HISTORY_OLDER" ]; then echo "Error: no value set for '-older' "; exit 1; fi
if [ "$RUND_HISTORY_TARGET" == "projects" ]; then RUND_HISTORY_KEEP_VALUE=0; fi

if [ "$RUND_JOB_STATUS" == "all" ]; then RUND_JOB_STATUS=""; fi
if [ ! -z "$RUND_JOB_STATUS" ]; then RUND_JOB_STATUS="--data-urlencode statusFilter=$RUND_JOB_STATUS"; fi

RUND_HISTORY_KEEP="--data-urlencode offset=${RUND_HISTORY_KEEP_VALUE}"

echo "------------------------------------"

# API access verification
sTemp=$( ${CURL_API_CMD}/1/projects 2>&1)
if [ $? -ne 0 ] || ! echo "$sTemp" | grep -i -q "apiversion"; then echoerr "Error: cannot contact rundeck through the API"; exit 1; fi


echo ""
echo "Gathering instance projects ..."
# cli :  rd projects list
CURL_API_VERSION=1
RUND_PROJECTS=$( ${CURL_API_CMD}/${CURL_API_VERSION}/projects )
if [ $? -ne 0 ]; then echoerr "Error: projects list - bad API query"; echoerr "$RUND_PROJECTS"; exit 1; fi

RUND_PROJECTS=$( echo "$RUND_PROJECTS" | grep -Po "<name>\K.*?(?=</name>)" )
echo "$RUND_PROJECTS"

while read -r sCurrentProject; do
        echo ""

        # jobs selected
        if [ "$RUND_HISTORY_TARGET" == "jobs" ]; then
                echo "Gathering project ${sCurrentProject}'s jobs ..."

                CURL_API_VERSION=17
                sCurrentProject_Jobs=$( ${CURL_API_CMD}/${CURL_API_VERSION}/project/${sCurrentProject}/jobs )
                if [ $? -ne 0 ]; then echoerr "Error: job list - bad API query"; echoerr "$sCurrentProject_Jobs"; exit 1; fi

                # tranform the xml data in single line, then add \n between job blocs
                sCurrentProject_Jobs=$( echo "$sCurrentProject_Jobs" | tr '\n' ' ' | sed 's#>[ \t]*<#><#g' | sed 's#</job><job#</job>\n<job#g' )
                
		# parsing sCurrentProject_Jobs content
                while read -r sCurrentJobData; do
			# forced pause between 2 jobs
			sleep "${RUND_SLEEP_DURATION_SEC}s"


                        # format : <job id='xxx-xxx-xx-xxx' href='...api-url...' ... ><name>...job name...</name>...</job>                        
                        sCurrentJob_id=$( echo "$sCurrentJobData" | grep -Po "id='\K.*?(?=' )" )
                        sCurrentJob_name=$( echo "$sCurrentJobData" | grep -Po "<name>\K.*?(?=</name>)" )

                        echo "- job $sCurrentJob_name : clearing history ..."
                        
                        # contrary to the cli, the api deletebulk executions doesn't directly allow an offset and/or a time filter
                        # start with retrieving the execution history ids
                        CURL_API_VERSION=14
                        sCurrentJobExecId=$( ${CURL_API_CMD}/${CURL_API_VERSION}/project/${sCurrentProject}/executions --data-urlencode jobIdListFilter=${sCurrentJob_id} --data-urlencode max=999 ${RUND_JOB_STATUS} ${RUND_HISTORY_KEEP} ${RUND_HISTORY_OLDER} )
                        if [ $? -ne 0 ]; then echoerr "Error: executions listing - bad API query"; echoerr "$sCurrentJobExecId"; exit 1; fi

			# check if there's no execution
			if [ -z "$sCurrentJobExecId" ] || echo "$sCurrentJobExecId" | grep -q "<executions count='0'"; then echo "  No execution found"; continue; fi


			# extract the execution ids
			sCurrentJobExecId=$( echo "$sCurrentJobExecId" | grep -Po "<execution id='\K.*?(?=' )" )
                        

                        # clear the execution history using the retrieved exec ids : single line, separated with ,
                        sCurrentJobExecId=$( echo "$sCurrentJobExecId" | tr '\n' ',' )
                        sCurrentJobExecId=${sCurrentJobExecId%,}

                        CURL_API_VERSION=12
                        # --header "Content-Length: 0"
                        sRet=$( ${CURL_API_CMD_POST}/${CURL_API_VERSION}/executions/delete --data-urlencode ids=${sCurrentJobExecId}  2>&1)
                        if [ $? -ne 0 ]; then echoerr "Error: executions deletebulk - bad API query"; echo "$sRet"; exit 1; fi
                        
                        sRet=$( echo "$sRet" | grep -Po "<successful count='\K.*?(?=' )" )
                        echo " Deleted $sRet executions."

                done <<< "$sCurrentProject_Jobs"

        # projects selected
        else
                echo "- clearing project $sCurrentProject history ..."
                
                # same player shoot again -- without any job id filter this time                
                CURL_API_VERSION=14
                sCurrentJobExecId=$( ${CURL_API_CMD}/${CURL_API_VERSION}/project/${sCurrentProject}/executions --data-urlencode max=999 ${RUND_JOB_STATUS} ${RUND_HISTORY_KEEP} ${RUND_HISTORY_OLDER} )
                if [ $? -ne 0 ]; then echoerr "Error: executions listing - bad API query"; echoerr "$sCurrentJobExecId"; exit 1; fi

		# check if there's no execution
		if [ -z "$sCurrentJobExecId" ] || echo "$sCurrentJobExecId" | grep -q "<executions count='0'"; then echo "  No execution found"; continue; fi

		# extract the execution ids
		sCurrentJobExecId=$( echo "$sCurrentJobExecId" | grep -Po "<execution id='\K.*?(?=' )" )

                
                # clear the execution history using the retrieved exec ids
                sCurrentJobExecId=$( echo "$sCurrentJobExecId" | tr '\n' ',' )
                sCurrentJobExecId=${sCurrentJobExecId%,}

                CURL_API_VERSION=12
                # --header "Content-Length: 0"
                sRet=$( ${CURL_API_CMD_POST}/${CURL_API_VERSION}/executions/delete --data-urlencode ids=${sCurrentJobExecId}  2>&1)
                if [ $? -ne 0 ]; then echoerr "Error: executions deletebulk - bad API query"; echoerr "$sRet"; exit 1; fi
                
                sRet=$( echo "$sRet" | grep -Po "<successful count='\K.*?(?=' )" )                        
                echo " Deleted $sRet executions."
        fi

done <<< "$RUND_PROJECTS"

echo ""
echo "done ."

