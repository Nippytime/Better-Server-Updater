#!/bin/bash
#
# Project Zomboid Dedicated Server - BSU Auto Restart Wrapper
#

###############################################################################
# The Linux launcher normally reads memory settings from ProjectZomboid64.json.
# This script preserves the normal Linux launch method and adds an automatic
# restart loop similar to the Windows BSU launcher.
###############################################################################

INSTDIR="$(cd "$(dirname "$0")" && pwd)"
cd "${INSTDIR}" || exit 1

RESTART_DELAY_SECONDS=15
STOP_FILE="BSU_STOP_RESTART.flag"
QUICK_EXIT_LIMIT_SECONDS=60
QUICK_EXIT_MAX=3
QUICK_EXIT_COUNT=0

# Stop the loop cleanly if this wrapper itself receives Ctrl+C / SIGTERM.
STOP_REQUESTED=0
trap 'STOP_REQUESTED=1; echo; echo "[BSU] Stop signal received. Restart loop will stop."' INT TERM

if ! "${INSTDIR}/jre64/bin/java" -version >/dev/null 2>&1; then
    echo "[BSU] Could not find or run ${INSTDIR}/jre64/bin/java"
    echo "[BSU] Put this file in your Project Zomboid Dedicated Server folder."
    exit 1
fi

if [ ! -x "${INSTDIR}/ProjectZomboid64" ]; then
    echo "[BSU] Could not find executable: ${INSTDIR}/ProjectZomboid64"
    echo "[BSU] Verify your Project Zomboid Dedicated Server installation."
    exit 1
fi

export PATH="${INSTDIR}/jre64/bin:$PATH"
export LD_LIBRARY_PATH="${INSTDIR}/linux64:${INSTDIR}:${INSTDIR}/jre64/lib/amd64:${LD_LIBRARY_PATH}"
JSIG="libjsig.so"

while true; do
    if [ "${STOP_REQUESTED}" -eq 1 ]; then
        break
    fi

    if [ -f "${STOP_FILE}" ]; then
        echo
        echo "[BSU] Stop file found: ${STOP_FILE}"
        echo "[BSU] Delete \"${STOP_FILE}\" to allow automatic restarts again."
        break
    fi

    START_SECONDS="$(date +%s)"

    clear
    echo "============================================================"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Project Zomboid dedicated server"
    echo "============================================================"
    echo "[BSU] To stop the restart loop, create: ${STOP_FILE}"
    echo

    LD_PRELOAD="${LD_PRELOAD}:${JSIG}" ./ProjectZomboid64 "$@"
    EXIT_CODE=$?

    END_SECONDS="$(date +%s)"
    RUN_SECONDS=$((END_SECONDS - START_SECONDS))

    if [ "${EXIT_CODE}" -eq 0 ]; then
        QUICK_EXIT_COUNT=0
    else
        if [ "${RUN_SECONDS}" -lt "${QUICK_EXIT_LIMIT_SECONDS}" ]; then
            QUICK_EXIT_COUNT=$((QUICK_EXIT_COUNT + 1))
        else
            QUICK_EXIT_COUNT=0
        fi
    fi

    echo
    echo "============================================================"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Server exited with code ${EXIT_CODE} after ${RUN_SECONDS} seconds."
    echo "============================================================"

    if [ "${STOP_REQUESTED}" -eq 1 ]; then
        break
    fi

    if [ "${EXIT_CODE}" -ne 0 ] && [ "${QUICK_EXIT_COUNT}" -ge "${QUICK_EXIT_MAX}" ]; then
        echo "[BSU] The server failed quickly ${QUICK_EXIT_COUNT} times in a row."
        echo "[BSU] Stopping the restart loop so it does not spam-crash forever."
        echo "[BSU] Check server-console.txt, Java memory settings, Workshop files, and the server install."
        break
    fi

    echo "[BSU] Restarting in ${RESTART_DELAY_SECONDS} seconds."
    echo "[BSU] Create \"${STOP_FILE}\" before the timer ends to stop the loop."

    # Sleep one second at a time so the stop file can cancel during the countdown.
    for ((i=0; i<RESTART_DELAY_SECONDS; i++)); do
        if [ "${STOP_REQUESTED}" -eq 1 ] || [ -f "${STOP_FILE}" ]; then
            break
        fi
        sleep 1
    done
done

echo
echo "[BSU] Restart loop stopped."
exit 0
