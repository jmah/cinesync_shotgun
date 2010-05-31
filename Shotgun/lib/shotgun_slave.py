#!/usr/bin/python

import sys
import yaml
import urllib2
from urlparse import urlparse
import cookielib
from shotgun_api3 import Shotgun

blob = yaml.load(sys.stdin)
method = sys.argv[1]

config = blob['config']
payload = blob['data']

sg = Shotgun(config['shotgun_url'], config['script_name'], config['script_api_key'], 'api3_preview')

if method == 'find':
  result = sg.find(payload['entity'], payload['filters'], payload['fields'], payload['order'], payload['filter_operator'], payload['limit'], payload['retired_only'])
elif method == 'find_one':
  result = sg.find_one(payload['entity'], payload['filters'], payload['fields'], payload['order'], payload['filter_operator'])
elif method == 'create':
  result = sg.create(payload['entity'], payload['data'])
elif method == 'update':
  result = sg.update(payload['entity'], payload['id'], payload['data'])
elif method == 'delete':
  result = sg.delete(payload['entity'], payload['id'])
elif method == 'upload':
  result = sg.upload(payload['entity'], payload['id'], payload['path'], payload['field_name'], payload['display_name'])
elif method == 'upload_thumbnail':
  result = sg.upload_thumbnail(payload['entity'], payload['id'], payload['path'])
elif method == 'schema_field_read':
  result = sg.schema_field_read(payload['entity'])
elif method == 'schema_field_create':
  result = sg.schema_field_create(payload['entity'], payload['type'], payload['name'], payload['attrs'])
elif method == '_url_for_attachment_id':
  entity_id = payload['id']

  # Do a lot of legwork (based on Shotgun.download_attachment())
  sid = sg._get_session_token()
  domain = urlparse(sg.base_url)[1].split(':',1)[0]
  cj = cookielib.LWPCookieJar()
  c = cookielib.Cookie('0', '_session_id', sid, None, False, domain, False, False, "/", True, False, None, True, None, None, {})
  cj.set_cookie(c)
  cookie_handler = urllib2.HTTPCookieProcessor(cj)
  urllib2.install_opener(urllib2.build_opener(cookie_handler))
  url = '%s/file_serve/attachment/%s' % (sg.base_url, entity_id)

  request = urllib2.Request(url)
  request.add_header('User-agent','Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; en-US; rv:1.9.0.7) Gecko/2009021906 Firefox/3.0.7')

  # Set result to a URL that can be accessed without a session cookie
  result = urllib2.urlopen(request).geturl()
else:
  print 'Unknown method: ' + method, sys.stderr
  exit(1)

if result != None:
  print yaml.dump(result)
