#Requires AutoHotkey v2
^Esc::ExitApp

; =====================================================
; Generic Username Password information, supports up to 50 pairs.
; It will cycle through and login all accounts before returning to
; the first pair on the list.  This is called the clock cycle restart.
; =====================================================

accounts := [
["username1", "password1"],
["username2", "password2"],
["username3", "password3"],
["username4", "password4"],
["username5", "password5"],
["username6", "password6"],
["username7", "password7"],
["username8", "password8"],
["username9", "password9"],
]

; =====================================================
; After roughly 2 hours (depending on systems), force-quitting
; the applications (necessary) will eventually cause new restarts
; to crash with errors.  Since the script heavily relies on 
; window names even with hardware ID tracking, all error boxes/windows
; must be closed before the restart function can continue to prevent 
; calling the wrong windows.
; =====================================================

SetTimer KillErrorPopups, 250

KillErrorPopups()
{
    for hwnd in WinGetList()
    {
        try
        {
            title := WinGetTitle(hwnd)
            class := WinGetClass(hwnd)

            ; Common crash/error dialogs
            if (
                InStr(title, "EXCEPTION")
                || InStr(title, "Unhandled exception")
                || InStr(title, "Error")
                || InStr(title, "Breakpoint")
                || InStr(title, "crash")
                || class = "#32770"   ; standard dialog box
            )
            {
                WinClose("ahk_id " hwnd)

                ; force kill if it stays open
                Sleep 500

                if WinExist("ahk_id " hwnd)
                {
                    try
                    {
                        pid := WinGetPID("ahk_id " hwnd)
                        ProcessClose(pid)
                    }
                }
            }
        }
    }
}

; =====================================================
; After force-quitting, the system needs time to process
; the shutdown before a new window can be opened.  Adjust
; the timer accordingly.  LaunchDelay is the time between
; application pairs opening.  In this case, the most optimal
; set up for my PC is roughly 3 minutes.
; =====================================================

pairs := []

launchDelay := 145000
restartDelay := 5000

; =====================================================
; Added a LIVE status window to visually see which pairs are
; active/disconnected/crashed/relaunching... etc.
; It also has a clock displaying time until next launch/relaunch
; and time difference between applications A and B, B and C, ... etc.
; =====================================================

statusMap := Map()

nextRestartTime := 0
countdownControls := Map()

statusGui := Gui("+AlwaysOnTop", "Pair Status Monitor")
statusGui.SetFont("s10", "Consolas")

statusControls := Map()

Loop 19
{
    pairNum := A_Index

    ; Pair label
    statusGui.AddText(
        "xm y+5 w60",
        "Pair " pairNum
    )

    ; Status
    statusControls[pairNum] := statusGui.AddText(
        "x+10 yp w180",
        "⚪ WAITING"
    )

    ; Countdown
    countdownControls[pairNum] := statusGui.AddText(
        "x+10 yp w140",
        ""
    )

    statusMap[pairNum] := "Waiting"
}

statusGui.Show("x1490 y0")

; =====================================================
; This is the live update function. Still updating to
; show what is relevant to see.
; =====================================================

UpdatePairStatus(pairNumber, status)
{
    global statusControls, statusMap

    statusMap[pairNumber] := status

    switch status
    {
        case "Active":
            text := "🟢 ACTIVE"

        case "Launching":
            text := "🟡 LAUNCHING"

        case "Restarting":
            text := "🟠 RESTARTING"

        case "Next Restart":
            text := "🔵 NEXT RESTART"

        case "Error":
            text := "🔴 ERROR"

        default:
            text := "⚪ " status
    }

    statusControls[pairNumber].Text := text
}

; =====================================================
; Live countdown in seconds.
; =====================================================

SetTimer UpdateCountdowns, 1000

UpdateCountdowns()
{
    global countdownControls, pairs, restartIndex, nextRestartTime, statusMap

    if (!nextRestartTime)
        return

    remaining := Ceil((nextRestartTime - A_TickCount) / 1000)

    if (remaining < 0)
        remaining := 0

    ; clear all
    for k, ctrl in countdownControls
        ctrl.Text := ""

    ; show on next pair
    if (pairs.Length >= restartIndex)
    {
        nextPair := pairs[restartIndex]

        ; only show if not currently restarting
        if (statusMap[nextPair.pairNumber] != "Restarting")
        {
            countdownControls[nextPair.pairNumber].Text :=
                "⏱ " remaining "s"
        }
    }
}

; =====================================================
; This section is dedicated to storing copy-paste text 
; on a clipboard as a variable.
; =====================================================

GenericScript1 :=
(
"###Generic_ScriptLayout
 "Put text/code here"
)

GenericScript2 :=
(
"###Generic_ScriptLayout
 "Put text/code here"
)

GenericScript3 :=
(
"###Generic_ScriptLayout
 "Put text/code here"
)

; =====================================================
; Settings for screen to sync coordinates to the screen
; instead of the application to avoid confusion.
; =====================================================

SetTitleMatchMode 2
CoordMode "Mouse", "Screen"

; =====================================================
; The initial launch sequence before indefinite restarts.
; =====================================================

pairNumber := 1

for pair in accounts
{
    user := pair[1]
    pass := pair[2]

    UpdatePairStatus(pairNumber, "Launching")

    pairs.Push(
        LaunchPair(pairNumber, user, pass)
    )

    UpdatePairStatus(pairNumber, "Active")

    Sleep launchDelay
    pairNumber++
}

UpdatePairStatus(1, "Next Restart")

; =====================================================
; This restart system activates after all applications
; has launched once.  After launching pairs 1, 2, 3, ... Z,
; it will go back to pair 1 (top of the list).
; =====================================================

restartIndex := 1

SetTimer UpdateNextRestartTime, 1000

UpdateNextRestartTime()
{
    global nextRestartTime, launchDelay, restartIndex

    if (!nextRestartTime)
        nextRestartTime := A_TickCount + launchDelay
}

Loop
{
    nextRestartTime := A_TickCount + launchDelay

    Sleep launchDelay

    RestartPair(restartIndex)

    restartIndex++

    if (restartIndex > pairs.Length)
        restartIndex := 1
}

; =====================================================
; The actual restart sequence.  It taskkills the tracked ID 
; pair, waits RestartDelay amount of seconds before re-opening.
; After relaunching, it sends the loop back to the original 
; launch function.
; =====================================================

RestartPair(index)
{
    global pairs, restartDelay

    pair := pairs[index]

    ; reset old "next restart"
    for i, v in pairs
    {
        if (statusMap[v.pairNumber] = "Next Restart")
            UpdatePairStatus(v.pairNumber, "Active")
    }

    UpdatePairStatus(pair.pairNumber, "Restarting")

    ; ============================================
    ; Kill Main Program
    ; ============================================

    try ProcessClose(pair.mainPID)
    catch
    {
        UpdatePairStatus(pair.pairNumber, "Error")
    }

    ; ============================================
    ; Kill Secondary Program
    ; ============================================

    try WinClose("Pair " pair.pairNumber " - Secondary")
    catch
    {
        UpdatePairStatus(pair.pairNumber, "Error")
    }

    Sleep 2000

    ; force kill if still alive as a safeguard
    try
    {
        if WinExist("Pair " pair.pairNumber " - Secondary")
        {
            secondaryPID := WinGetPID("Pair " pair.pairNumber " - Secondary")
            ProcessClose(secondaryPID)
        }
    }
    catch

    Sleep restartDelay

    ; ============================================
    ; Relaunching sequence (same as before).
    ; ============================================

    UpdatePairStatus(pair.pairNumber, "Launching")

    newPair := LaunchPair(
        pair.pairNumber,
        pair.user,
        pair.pass
    )

    pairs[index] := newPair

    UpdatePairStatus(pair.pairNumber, "Active")

    ; ============================================
    ; Identifies the next restart with timer.
    ; ============================================

    nextIndex := index + 1

    if (nextIndex > pairs.Length)
        nextIndex := 1

    nextPair := pairs[nextIndex]

    UpdatePairStatus(nextPair.pairNumber, "Next Restart")
}

; =====================================================
; This is the main function in our script.  It launches
; 2 applications (in order) so that the secondary application
; injects data and automated instructions to the primary.
; =====================================================

LaunchPair(pairNumber, user, pass)
{
    global secondaryScript

    ; =================================================
    ; This function launches the main application.  This is done 
    ; directly through system files instead of clicking and is
    ; much for efficient for stability.  Edit the drive location,
    ; my program is in SATA so I will use E: drive.
    ; =================================================

    Run '"E:\Primary\Bin\GenericFile.exe"
        , "E:\Generic\Bin"
        , , &primaryPID

    WinWait "ahk_exe GenericFile.exe",, 30
    WinWaitActive "ahk_exe GenericFile.exe"

    wins := WinGetList("ahk_exe GenericFile.exe")
    genericHWND := wins[1]

    ; =================================================
    ; Launch Secondary application right after primary finishes.
    ; =================================================

    Run '"E:\Secondary\Secondary.exe"'
        , "E:\Secondary"
        , , &secondaryPID

    WinWait "ahk_exe Secondary.exe",, 30
    WinWaitActive "ahk_exe Secondary.exe"

    Sleep 5000

    wins := WinGetList("ahk_exe Secondary.exe")
    secondaryHWND := wins[1]

    ; =================================================
    ; Move primary window to X,Y coordinates.
    ; =================================================

    WinRestore primaryHWND
    WinMove -7, 409,,, primaryHWND

    Sleep 500

    WinSetTitle "Pair " pairNumber " - Primary", "ahk_id " primaryHWND

    ; =================================================
    ; Move secondary window to X1,Y1 coordinates.
    ; =================================================

    WinRestore secondaryHWND
    WinMove 1000, 483,,, secondaryHWND

    Sleep 500

    WinSetTitle "Pair " pairNumber " - Secondary", "ahk_id " secondaryHWND

    ; =================================================
    ; Login Primary application, the field syncs perfectly
    ; with coordinates moved.
    ; =================================================

    WinActivate "ahk_id " primaryHWND
    Sleep 1000

    Click 350, 733, 2
    Sleep 100
    SendText user

    Click 350, 773, 2
    Sleep 100
    SendText pass

    Sleep 100
    Send "{Enter}"

    Sleep 5000

    MouseMove 400, 800
    Sleep 200
    Click 400, 800

    Sleep 4000

    MouseMove 400, 1015
    Sleep 200
    Click 400, 1015

    Sleep 6000

    Send "{Esc}"
    Sleep 400

    Send "{Esc}"
    Sleep 400

    MouseMove 141, 953
    Sleep 200
    Click 141, 953

    ; =================================================
    ; Paste script instructions into secondary application.
    ; =================================================

    WinActivate "ahk_id " secondaryHWND
    Sleep 500

    Click 1441, 565
    Sleep 200

    Click 1062, 645
    Sleep 200

    SendText genericScript

    Sleep 1000

    Click 1266, 882

    Sleep 1000

    WinMinimize "ahk_id " primaryHWND
    WinMinimize "ahk_id " secondaryHWND

    ; =================================================
    ; Return Pair Object to be stored and checked later.
    ; =================================================

    return {
        pairNumber: pairNumber,
        user: user,
        pass: pass,
        primaryPID: primaryPID
    }
}