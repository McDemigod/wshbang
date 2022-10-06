:; echo "🪟❗You're not running in Windows, #! already works!🦝"; return 1

@echo off
@setlocal

:: Change the codepage to 65001 for Unicode; store the old one.
for /f "tokens=*" %%i in ( 'chcp' ) do set cp=%%i
set cp=%cp:Active code page: =%
chcp 65001 > nul

:: Associating through the prompt seems to drop the `%*` at the end of
:: `shell\open\command` in the registry; this breaks argument passing.
:: Add it back to HKCU; that doesn't need special privilege.
:: Notes:
::   %~nx0  current script filename.ext, no quotes; necessary in case we're
::          in Powershell, which apparently passes the full pathname as %0
::   %~f0   Full pathname; still uncertain what he proper format is here...
reg add HKEY_CURRENT_USER\Software\Classes\Applications\%~nx0\shell\open\command /ve /d "\"%~f0\" \"%%1\" %%*" /f > nul
if %errorlevel% NEQ 0 (
    echo 🪟❗ ERROR: Can't register shell command. 🦝 1>&2
    goto :cleanup_exit
)

:: If invoked without any arguments, Print usage information.
if [%1]==[] (
    goto :print_help
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
        if %errorlevel% NEQ 0 (
            echo 🪟❗ ERROR: Can't associate with filetype. 🦝 1>&2
            goto :cleanup_exit
        )
    ) else (
        :: assoc the extension in %2, ftype too while we're at it.
        powershell Start-Process cmd.exe '/c "assoc %2=wshbang%2 && ftype wshbang%2=\"^"%~f0\^" \^"%%1\^" %%*"' -Verb runAs
        if %errorlevel% NEQ 0 (
            echo 🪟❗ ERROR: Can't associate with filetype. 🦝 1>&2
            goto :cleanup_exit
        )
    )
    :: Don't actually run.
    goto :cleanup_exit
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
    goto :cleanup_exit
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
        goto :cleanup_exit
    ) else (
        echo 🪟❗ ERROR: %unix_command% without executable. 🦝 1>&2
        set errorlevel=1057
        goto :cleanup_exit
    )
)

:: Accept Windows paths directly (probably not going to happen...)
if exist %unix_command% (
    %unix_command% %unix_argument% %*
    goto :cleanup_exit
)

:: Do we find the the command in our mapfile?
set map_file="%~dp0\unix_windows.tab"
if exist %map_file% (
    for /f "tokens=2" %%a in ('findstr /b /c:"%unix_command%	" %map_file% ') do (
        :: Does it exist?
        if exist %%a (
            :: If so, run it!
            %%a %unix_argument% %*
            goto :cleanup_exit
        )
    )
)

:: Prompt the user for an executable.
:: Adding `con` here should force this, instead of stealing from stdin:
:prompt_for_executable
set windows_command=
echo 🪟❗: Enter path to executable (leave blank to quit^): 🦝
set /p windows_command=< con

if not defined windows_command (
    echo 🪟❗ INTERRUPT: Abortions for all! 🦝 1>&2
    set errorlevel=7
    goto :cleanup_exit
)

:: Does *that* exist?
if not exist %windows_command% (
    echo 🪟❗: Not seeing it. Try again? 🦝
    goto :prompt_for_executable
) else (
    echo %unix_command%	%windows_command% >> %map_file%
    %windows_command% %unix_argument% %*
    goto :cleanup_exit
)

:: Print help text (usage info)
:print_help
echo wshbang - #! support for Windows
echo:
echo Description
echo     🪟❗ wshbang is a batch script that allows Windows users to use the #!
echo     interpreter directive common to *nix systems. That is, instead of
echo     associating all files with a given file extension a single interpreter,
echo     files will be able to define their own interpreter in via a #! header. More
echo     importantly, options/arguments and standard input should work as expected,
echo     which is frequently not the case given Windows association handling.
echo:
echo Associations
echo     wshbang must still be associated with given file extensions. From then on,
echo     Windows invokes wshbang to interpret the file, which in turn passes control
echo     to the interpreter of choice. Association is handled differently in recent
echo     and older versions of Windows. Instructions for each is given below; these
echo     do not conflict, try both if you are uncertain which is appropriate.
echo:
echo     Windows ≥ 10
echo         Starting in Windows 10, programs are no longer able to alter file
echo         associations; users may do so in settings. The simplest way to do so is
echo         to right-click your target file ^& select "Open with"; navigate to /
echo         select wshbang ^& check the "Always use..." box to set the default from
echo         now on.
echo     Windows ^< 10
echo         In earlier versions of Windows, wshbang may set associations directly.
echo         The `-a [extension]` option described below will prompt for elevation
echo         (per UAC settings) ^& set associations appropriately.
echo:
echo Format
echo     wshbang expects `#!` as first two bytes of the interpreted file, followed by
echo     a path to the executable ^& up to one option. Whitespace is not permitted
echo     before the `#!`, but is optional ^& permitted between it and the executable
echo     path. Furthermore, it delimits the interpreter ^& option; it is not allowed
echo     in the executables path.
echo:
echo Behavior
echo     If the first two bytes found are not `#!`, wshbang raises an openwith
echo     prompt as common for files with no association.
echo     Windows-native paths are useable directly: if the interpreter term is found
echo     in the working directory or the search path (%%PATH%%), it is invoked
echo     directly.
echo     Path searching translates across Unix/Windows: if the executable path is
echo     `/usr/bin/env` or `/bin/env`, an executable must follow as an option to
echo     `env` (or an error is raised). This executable is invoked directly. Note the
echo     shell will parse the %%PATHEXT%% variable to determine viable extensions; eg.
echo     Unix's `python` will ultimately translate to Windows' `python.exe`.
echo     Full Unix paths are mapped to Windows paths: The directory containing this
echo     script is searched for a file named `unix_windows.tab`, a tab-delimited file
echo     mapping from Unix to Windows executables. Rows are parsed in sequence; if
echo     the Unix executable is matched, the windows executable will be path searched
echo     (%%PATH%%, %%PATHEXT%% apply). If a suitable executable is not found, the user
echo     is prompted to enter one. Note: this prompt does not accept standard input
echo     from a `^|` pipeline; this is intentional to leave it intact for the
echo     interpreted script. In non-interactive contexts, instead append to
echo     `unix_windows.tab` in advance:
echo:
echo         $ echo /bin/python\tpython.exe ^>^> unix_windows.tab
echo         $ echo Input of the standard variety ^| my_script.py
echo:
echo     interrupt signals may not propogate during this prompt; to abort simply
echo     enter an empty value.
echo:
echo Arguments
echo     -a [file extension]
echo         Associate wshbang (as in older Windows versions). This will prompt to
echo         elevate a process, per UAC settings. Without a file extension, this will
echo         register the script ^& proper invocation. If a file extension is given,
echo         it will additional associate to that particular filetype. Include the
echo         dot character, eg `.ext`! To associate with plain files -- those with no
echo         extension, pass the dot character alone `.`.
echo:
echo 🦝
goto :cleanup_exit

:: Exit gracefully (returning codepage)
:cleanup_exit
chcp %cp% > nul
exit /b %errorlevel%
