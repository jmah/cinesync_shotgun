#!/bin/sh

killall -c cineSync

CURR_USER_LINK=/private/tmp/CurrentUser
rm -f "$CURR_USER_LINK" && ln -s "$HOME" "$CURR_USER_LINK"
