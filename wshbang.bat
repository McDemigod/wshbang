:; echo "🪟❗You're not running in Windows, #! already works!🦝"; return 1
@echo off
@setlocal

:: Associating through the prompt seems to drop the `%*` at the end of
:: `shell\open\command` in the registry; this breaks argument passing.
:: Add it back to HKCU; that doesn't need special privilege.
:: Notes:
::   %~nx0  current script filename.ext, no quotes; necessary in case we're
::          in Powershell, which apparently passes the full pathname as %0
::   %~f0   Full pathname; still uncertain what he proper format is here...
reg add HKEY_CURRENT_USER\Software\Classes\Applications\%~nx0\shell\open\command /ve /d "\"%~f0\" \"%%1\" %%*" /f > nul
if %errorlevel% NEQ 0 (
    echo #! error: Can't register shell command. 1>&2
    exit /b %errorlevel%
)

:: If invoked without any arguments, Print usage information.
if [%1]==[] (
    type "%~dp0\help.txt" 1>&2
    exit /b %errorlevel%
)

:: TODO: add -r [extension] like -a below to handle associations via
::       the registry (separate option since this doesn't need elevation).

:: If invoked with -a [extension], elevate & associate using assoc/ftype:
::   This should work for older versions of Windows, but has no effect in recent
::   versions.
if "%1" == "-a" (
    if [%2]==[] (
        :: No extensions given, just do ftype:
        powershell.exe -command Start-Process -Verb runAs cmd.exe '/c" ftype wshbang=%~f0 %%1 %%*"'
        exit /b %errorlevel%
    ) else (
        :: assoc the extension in %2, ftype too while we're at it.
        powershell Start-Process cmd.exe '/k "assoc %2=wshbang%2 && ftype wshbang%2=\"^"%~f0\^" \^"%%1\^" %%*"' -Verb runAs
        exit /b %errorlevel%
    )
)

:: Parse the header
set /p header=< %1
set directive=%header:~2%

:: Rescue old behavior; if the header does not begin with #!, prompt (openwith).
:: Note this doesn't pass arguments / stdio, but that isn't typical in this case
:: anyway.
::   TODO: openwith.exe does not seem to pop when invoked here,
::         Rundll32 is a workaround.
if not "%header:~0,2%" == "#!" (
    Rundll32 Shell32.dll,OpenAs_RunDLL %1
    exit /b %errorlevel%
)

:: Split the directive to find what it would have been in Unix:
for /f "tokens=1,2" %%a in ( "%directive%" ) do (
    set unix_command=%%a
    set unix_argument=%%b
)

:: If `env` used in Unix to search the path, just invoke `unix_argument`.
::   TODO: accept `/any/path/to/env` instead of these specific paths?
set search_path=0
if "%unix_command%" == "/usr/bin/env" ( set search_path=1 )
if "%unix_command%" == "/bin/env"     ( set search_path=1 )
if %search_path% equ 1 (
    if defined unix_argument (
        %unix_argument% %*
        exit /b %errorlevel%
    ) else (
        echo #! error: %unix_command% without executable 1>&2
        exit /b 1057
    )
)

:: Accept Windows paths directly (probably not going to happen...)
if exist %unix_command% (
    %unix_command% %unix_argument% %*
    exit /b %errorlevel%
)

:: Do we find the the command in our mapfile?
set map_file="%~dp0\unix_windows.tab"
if exist %map_file% (
    for /f "tokens=2" %%a in ('findstr /b /c:"%unix_command%	" %map_file% ') do (
        :: Does it exist?
        if exist %%a (
            :: If so, run it!
            %%a %unix_argument% %*
            exit /b %errorlevel%
        )
    )
)

:: Prompt the user for an executable.
:: Adding `con` here should force this, instead of stealing from stdin:
:prompt_for_executable
set windows_command=
echo Enter path to executable (leave blank to quit^):
set /p windows_command=< con

if not defined windows_command (
    echo #! interrupt: Abortions for all! 1>&2
    exit /b 7
)

:: Does *that* exist?
if not exist %windows_command% (
    echo Not seeing it. Try again?
    goto :prompt_for_executable
) else (
    echo %unix_command%	%windows_command% >> %map_file%
    %windows_command% %unix_argument% %*
    exit /b %errorlevel%
)
