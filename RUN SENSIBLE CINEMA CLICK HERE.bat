@setlocal
@rem disable any local rubyopt settings...
@set RUBYOPT=
@echo This window will display lots of debug message output!
@cd sensible-cinema && java -cp "./vendor/cache/jruby-complete-1.5.5.jar" org.jruby.Main bin\sensible-cinema || echo you need to install java first! Please report back the error you see! && pause
@rem taskkill /f /im mencoder.exe