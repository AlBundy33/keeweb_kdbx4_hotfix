# keeweb_kdbx4_hotfix

This Dockerfile creates a build of keeweb 1.18.7 with kdbxweb 2.0.4 with patches and pull requests to fix:

# ensure to write LastModificationTime in base64 to not currupt the database
PR: https://github.com/keeweb/keeweb/issues/2001

see https://keepass.info/help/kb/kdbx_4.1.html#cd_lastmod

this is needed if you want to open the database also in KeePass

# bugfix for resetting the keyfile
PR: https://github.com/keeweb/keeweb/issues/1924
