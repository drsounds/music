/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */
 
using Gee;

public class BeatBox.Playlist : Object {
	public TreeViewSetup tvs;
	private Gee.HashMap<Media, int> _media; // Media, 1
	
	public int rowid { get; set; }
	public string name { get; set; }

	public signal void media_added (Gee.Collection<Media> media);
	public signal void media_removed (Gee.Collection<Media> media);
	public signal void cleared ();
	
	public Playlist() {
		name = "";
		tvs = new TreeViewSetup(MusicListView.MusicColumn.NUMBER, Gtk.SortType.ASCENDING, ViewWrapper.Hint.PLAYLIST);
		_media = new Gee.HashMap<Media, int>();
	}
	
	public Playlist.with_info(int rowid, string name) {
		_media = new Gee.HashMap<Media, int>();
		tvs = new TreeViewSetup(MusicListView.MusicColumn.NUMBER, Gtk.SortType.ASCENDING, ViewWrapper.Hint.PLAYLIST);
		this.rowid = rowid;
		this.name = name;
	}
		
	public Gee.Collection<Media> media () {
		return _media.keys;
	}
	
	public void add_media (Collection<Media> to_add) {
		var added_media = new Gee.LinkedList<Media> ();
		foreach (var m in to_add) {
			if (m != null) {
				_media.set (m, 1);
				added_media.add (m);
			}
		}

		media_added (added_media);
	}

	public void remove_media (Collection<Media> to_remove) {
		var removed_media = new Gee.LinkedList<Media> ();
		foreach (var m in to_remove) {
			if (m != null && _media.has_key (m)) {
				_media.unset (m);
				removed_media.add (m);
			}
		}

		media_removed (removed_media);
	}
	
	public void clear() {
		_media = new HashMap<Media, int>();
		cleared ();
	}
	
	public void media_from_string(string media, LibraryManager lm) {
		string[] media_strings = media.split(",", 0);
		
		int index;
		var new_media = new Gee.LinkedList<Media> ();
		for (index = 0; index < media_strings.length - 1; ++index) {
			int id = int.parse (media_strings[index]);
			var m = lm.media_from_id (id);
			if (m != null) {
				_media.set (m, 1);
				new_media.add (m);
			}
		}
		media_added (new_media);
	}
	
	public string media_to_string (LibraryManager lm) {
		string rv = "";
		
		foreach (var m in _media.keys) {
			if (m != null)
				rv += m.rowid.to_string() + ",";
		}

		return rv;
	}

	public bool contains_media (Media m) {
		return _media.has_key (m);
	}

	public GPod.Playlist get_gpod_playlist() {
		GPod.Playlist rv = new GPod.Playlist(name, false);
		
		rv.sortorder = tvs.get_gpod_sortorder();
		
		return rv;
	}
	
	// how to specify a file?
	public bool save_playlist_m3u (LibraryManager lm, string folder) {
		bool rv = false;
		string to_save = "#EXTM3U";
		
		foreach(var s in _media.keys) {
			if (s == null)
				continue;

			to_save += "\n\n#EXTINF:" + s.length.to_string() + ", " + s.artist + " - " + s.title + "\n" + File.new_for_uri(s.uri).get_path();
		}
		
		File dest = GLib.File.new_for_path(Path.build_path("/", folder, name.replace("/", "_") + ".m3u"));
		try {
			// find a file path that doesn't exist
			string extra = "";
			while((dest = GLib.File.new_for_path(Path.build_path("/", folder, name.replace("/", "_") + extra + ".m3u"))).query_exists()) {
				extra += "_";
			}
			
			var file_stream = dest.create(FileCreateFlags.NONE);
			
			// Write text data to file
			var data_stream = new DataOutputStream (file_stream);
			data_stream.put_string(to_save);
			rv = true;
		}
		catch(Error err) {
			warning ("Could not save playlist %s to m3u file %s: %s\n", name, dest.get_path(), err.message);
		}
		
		return rv;
	}
	
	public bool save_playlist_pls(LibraryManager lm, string folder) {
		bool rv = false;
		string to_save = "[playlist]\n\nNumberOfEntries=" + _media.size.to_string() + "\nVersion=2";
		
		int index = 1;
		foreach(var s in _media.keys) {
			if (s == null)
				continue;
			
			to_save += "\n\nFile" + index.to_string() + "=" + File.new_for_uri(s.uri).get_path() + "\nTitle" + index.to_string() + "=" + s.title + "\nLength" + index.to_string() + "=" + s.length.to_string();
			++index;
		}
		
		File dest = GLib.File.new_for_path(Path.build_path("/", folder, name.replace("/", "_") + ".pls"));
		try {
			// find a file path that doesn't exist
			string extra = "";
			while((dest = GLib.File.new_for_path(Path.build_path("/", folder, name.replace("/", "_") + extra + ".pls"))).query_exists()) {
				extra += "_";
			}
			
			var file_stream = dest.create(FileCreateFlags.NONE);
			
			// Write text data to file
			var data_stream = new DataOutputStream (file_stream);
			data_stream.put_string(to_save);
			rv = true;
		}
		catch(Error err) {
			warning ("Could not save playlist %s to pls file %s: %s\n", name, dest.get_path(), err.message);
		}
		
		return rv;
	}
	
	public static bool parse_paths_from_m3u(LibraryManager lm, string path, ref Gee.LinkedList<string> locals, ref Gee.LinkedList<Media> stations) {
		// now try and load m3u file
		// if some files are not found by media_from_file(), ask at end if user would like to import the file to library
		// if so, just do import_individual_files
		// if not, do nothing and accept that music files are scattered.
		
		var file = File.new_for_path(path);
		if(!file.query_exists())
			return false;
		
		try {
			string line;
			string previous_line = "";
			var dis = new DataInputStream(file.read());
			
			while ((line = dis.read_line(null)) != null) {
				if(line.has_prefix("http:/")) {
					Media s = new Media(line);
					s.mediatype = Media.MediaType.STATION;
					
					s.album_artist = _("Radio Station");
					
					if(s.length <= 0)
						stations.add(s);
					else
						locals.add(line);
				}
				else if(line[0] != '#' && line.replace(" ", "").length > 0) {
					locals.add(line);
				}
				
				previous_line = line;
			}
		}
		catch(Error err) {
			warning ("Could not load m3u file at %s: %s\n", path, err.message);
			return false;
		}
		
		return true;
	}
	
	public static bool parse_paths_from_pls(LibraryManager lm, string path, ref Gee.LinkedList<string> locals, ref Gee.LinkedList<Media> stations) {
		var files = new HashMap<int, string>();
		var titles = new HashMap<int, string>();
		var lengths = new HashMap<int, string>();
		
		var file = File.new_for_path(path);
		if(!file.query_exists())
			return false;
		
		try {
			string line;
			var dis = new DataInputStream(file.read());
			
			while ((line = dis.read_line(null)) != null) {
				if(line.has_prefix("File")) {
					parse_index_and_value("File", line, ref files);
				}
				else if(line.has_prefix("Title")) {
					parse_index_and_value("Title", line, ref titles);
				}
				else if(line.has_prefix("Length")) {
					parse_index_and_value("Length", line, ref lengths);
				}
			}
		}
		catch(Error err) {
			warning ("Could not load m3u file at %s: %s\n", path, err.message);
			return false;
		}
		
		foreach(var entry in files.entries) {
			if(entry.value.has_prefix("http:/")/* && lengths.get(entry.key) != null && int.parse(lengths.get(entry.key)) <= 0*/)  {
				Media s = new Media(entry.value);
				s.mediatype = Media.MediaType.STATION;
				s.album_artist = titles.get(entry.key);
				
				if(s.album_artist == null)
					s.album_artist = "Radio Station";
				
				stations.add(s);
			}
			else {
				locals.add(entry.value);
			}
		}
		
		
		return true;
	}
	
	public static void parse_index_and_value(string prefix, string line, ref HashMap<int, string> map) {
		int index;
		string val;
		string[] parts = line.split("=", 2);
		
		index = int.parse(parts[0].replace(prefix,""));
		val = parts[1];
		
		map.set(index, val);
	}
}
