Moving pieces
=============

The whole data pipeline is composed of:
 * Warriors -- they scrape G+ and produce `miniwarc` files (tens of MB each) that they upload to Rsync targets
 * Rsync targets -- they receive `miniwarc` files, recompress them into larger `megawarc` files (tens of GB each), and upload then to IA
 * IA -- final destination of `megawarc` files
 
The coordination part of the pipeline consists of:
 * The tracker (tracker.archiveteam.org) -- it assigns work items (opaque IDs) and Rsync targets to warriors
 * Work item server -- it serves static files that contain lists of URLs that belong to a particular work item
 
Status
======

Current bottleneck is rsync targets.
