A Nagios/Icinga plugin to check remote monit installations.

This can be used in scenarios, when using monit as node centric montitoring tools
and on top using Icinga to monitor a whole environment.

This gives you feedback of there are any unmoniorted monit checks.

# Background

This plugin is based on Jens Braeuer's remote icinga plugin: https://github.com/jbraeuer/check_remote_icinga

# Installation

## As file

```
gem install excon
cp check_monit.rb /usr/lib/nagios/plugins
```

## As Debian package

1. package `excon` as Debian package (use https://github.com/jordansissel/fpm)
1. `dpkg-buildpackage -b`

# Want to improve this?

Send me your changes via pull-request.

# License

GPLv3

# Authors

Hajo Eichler
Jens Braeuer
