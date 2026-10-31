# The layout of the InvoicesTracker disk image, as dmgbuild reads it: a window
# with the app on the left and a link to /Applications on the right.
#
# The lane runs it as
#   dmgbuild -s dmg_settings.py -D app=<path of the .app> [-D volicon=<path of an .icns>] <volume name> <dmg>
# and dmgbuild puts the -D values in `defines`.
import os.path
app = defines['app']
app_name = os.path.basename(app)
files = [app]
symlinks = {'Applications': '/Applications'}
icon = defines.get('volicon')
format = 'UDZO'
window_rect = ((200, 120), (600, 400))
icon_size = 128
icon_locations = {app_name: (150, 190), 'Applications': (450, 190)}
hide_extensions = [app_name]
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
