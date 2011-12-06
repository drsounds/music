/*-
 * Copyright (c) 2011       Scott Ringwelski <sgringwe@mtu.edu>
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
using Gtk;

public class BeatBox.PodcastListView : ContentView, ScrolledWindow {
	public BeatBox.LibraryManager lm;
	public BeatBox.LibraryWindow lw;
	TreeView view;
	PodcastTreeModel podcast_model;
	
	Collection<int> _show_next; // these are populated if necessary when user opens this view.
	//private Collection<int> _songs;
	Collection<int> _showing_songs;
	LinkedList<string> _columns;
	
	int relative_id;// if playlist, smart playlist, etc.
	ViewWrapper.Hint hint; // playlist, queue, smart_playlist, etc. changes how it behaves.
	string sort_column;
	SortType sort_direction;
	bool playlistSaveTimeoutAdded;
	bool removing_songs;
	
	bool _is_current_view;
	bool _is_current;
	bool dragging;
	
	LinkedList<string> timeout_search;//stops from doing useless search (timeout)
	string last_search;//stops from searching same thing multiple times
	bool showing_all; // stops from searching unnecesarilly when changing b/w 0 words and search ViewWrapper.Hint, etc.
	
	bool scrolled_recently;
	
	CellDataFunctionHelper cellHelper;
	
	//for header column chooser
	Menu columnChooserMenu;
	CheckMenuItem columnEpisode; // episode
	CheckMenuItem columnName; // name
	CheckMenuItem columnLength;
	CheckMenuItem columnArtist;
	CheckMenuItem columnDate;
	CheckMenuItem columnRating;
	CheckMenuItem columnComments;
	CheckMenuItem columnCategory;
	
	//for song list right click
	Menu songMenuActionMenu;
	MenuItem songEditSong;
	MenuItem songFileBrowse;
	MenuItem songMenuQueue;
	MenuItem songMenuNewPlaylist;
	MenuItem songMenuAddToPlaylist; // make menu on fly
	//MenuItem songRateSong;
	//Menu songRateSongMenu;
	RatingWidgetMenu rating_item;
	MenuItem songRemove;
	
	Gdk.Pixbuf starred;
	Gdk.Pixbuf not_starred;
	
	// for editing cells in-treeview
	CellRendererText cellTrack;
	CellRendererText cellTitle;
	CellRendererText cellLength;
	CellRendererText cellArtist;
	CellRendererText cellAlbum;
	CellRendererText cellGenre;
	CellRendererText cellYear;
	CellRendererPixbuf cellRating;
	CellRendererText cellSkips;
	CellRendererText cellPlays;
	CellRendererText cellBitrate;
	
	
	//public signal void view_being_searched(string key);
	
	/*public bool is_current {
		get { return _is_current; }
		set {
			_is_current = value;
			podcast_model.is_current = value;
		}
	}*/
	
	/* interface functions */
	public void set_is_current(bool val) {
		_is_current = val;
		podcast_model.is_current = val;
	}
	
	public bool get_is_current() {
		return _is_current;
	}
	
	public void set_is_current_view(bool val) {
		_is_current_view = val;
	}
	
	public bool get_is_current_view() {
		return _is_current_view;
	}
	
	public void set_hint(ViewWrapper.Hint the_hint) {
		hint = the_hint;
		updateSensitivities();
	}
	
	public ViewWrapper.Hint get_hint() {
		return hint;
	}
	
	public void set_relative_id(int id) {
		relative_id = id;
	}
	
	public int get_relative_id() {
		return relative_id;
	}
	
	public void set_show_next(Collection<int> songs) {
		_show_next = songs;
	}
	
	public Collection<int> get_songs() {
		return podcast_model.getOrderedSongs();
	}
	
	public void set_as_current_list(int song_id) {
		bool shuffle = (lm.shuffle == LibraryManager.Shuffle.ALL);
		
		lm.clearCurrent();
		TreeIter iter;
		for(int i = 0; podcast_model.get_iter_from_string(out iter, i.to_string()); ++i) {
			Value id;
			podcast_model.get_value(iter, 0, out id);
			
			lm.addToCurrent(id.get_int());
			
			if(lm.song_info.song != null && lm.song_info.song.rowid == id.get_int() && song_id == 0)
				lm.current_index = i;
			else if(lm.song_info.song != null && song_id == id.get_int())
				lm.current_index = i;
		}
		
		set_is_current(true);
		
		if(lm.song_info.song != null)
			podcast_model.updateSong(lm.song_info.song.rowid, get_is_current());
			
		if(shuffle)
			lm.setShuffleMode(LibraryManager.Shuffle.ALL);
	}
	
	public void populate_view() {
		/** NOTE: This could have a bad effect if user coincidentally
		 * searches for something that has same number of results as 
		 * a different search. However, this cuts lots of unecessary
		 * loading of lists/icon lists */
		/*if(lw.searchField.get_text() == "" && _showing_songs.size == songs.size && ViewWrapper.Hint != ViewWrapper.Hint.HISTORY && ViewWrapper.Hint != ViewWrapper.Hint.QUEUE && !force) {
			return;
		}*/
		if(_show_next == _showing_songs) {
			return;
		}
		
		if(_show_next != _showing_songs) {
			_showing_songs = _show_next;
		}
		
		view.freeze_child_notify();
		view.set_model(null);
		
		int sort_col;
		SortType sort_dir;
		podcast_model.get_sort_column_id(out sort_col, out sort_dir);
		
		podcast_model = new PodcastTreeModel(lm, get_column_strings(), lm.nowPlayingIcon);
		podcast_model.is_current = _is_current;
		
		var hPos = this.vadjustment.get_value();
		
		podcast_model.append_songs(_showing_songs, false);
		
		podcast_model.set_sort_column_id(sort_col, sort_dir);
		
		if(lm.song_info.song != null)
			podcast_model.updateSong(lm.song_info.song.rowid, get_is_current());
		
		view.set_model(podcast_model);
		view.thaw_child_notify();
		
		if(get_is_current() && lm.song_info.song != null)
			scrollToCurrent();
		else
			this.view.scroll_to_point(0, (int)hPos);
		
		set_statusbar_text();
		
		if(get_is_current())
			set_as_current_list(0);
	}
	
	public void set_statusbar_text() {
		uint count = 0;
		uint total_time = 0;
		uint total_mbs = 0;
		
		foreach(int id in _showing_songs) {
			++count;
			total_time += lm.song_from_id(id).length;
			total_mbs += lm.song_from_id(id).file_size;
		}
		
		string fancy = "";
		if(total_time < 3600) { // less than 1 hour show in minute units
			fancy = (total_time/60).to_string() + " minutes";
		}
		else if(total_time < (24 * 3600)) { // less than 1 day show in hour units
			fancy = (total_time/3600).to_string() + " hours";
		}
		else { // units in days
			fancy = (total_time/(24 * 3600)).to_string() + " days";
		}
		
		string fancy_size = "";
		if(total_mbs < 1000)
			fancy_size = ((float)(total_mbs)).to_string() + " MB";
		else 
			fancy_size = ((float)(total_mbs/1000.0f)).to_string() + " GB";
		
		lw.set_statusbar_text(count.to_string() + " items, " + fancy + ", " + fancy_size);
	}
	
	/* music tree view specific functions */
	public Collection<int> get_showing_songs() {
		return podcast_model.getOrderedSongs();
	}
	
	public LinkedList<TreeViewColumn> get_columns() {
		var rv = new LinkedList<TreeViewColumn>();
		
		foreach(TreeViewColumn tvc in view.get_columns())
			rv.add(tvc);
		
		return rv;
	}
	
	public LinkedList<string> get_column_strings() {
		var rv = new LinkedList<string>();
		
		foreach(TreeViewColumn tvc in view.get_columns())
			rv.add(tvc.title);
		
		return rv;
	}
	
	/**
	 * for sort_id use 0+ for normal, -1 for auto, -2 for none
	 */
	public PodcastListView(BeatBox.LibraryManager lmm, BeatBox.LibraryWindow lww, string sort, Gtk.SortType dir, ViewWrapper.Hint the_hint, int id) {
		lm = lmm;
		lw = lww;
		
		//_songs = new LinkedList<int>();
		_showing_songs = new LinkedList<int>();
		_columns = new LinkedList<string>();
		
		last_search = "";
		timeout_search = new LinkedList<string>();
		showing_all = true;
		removing_songs = false;
		
		sort_column = sort;
		sort_direction = dir;
		hint = the_hint;
		playlistSaveTimeoutAdded = false;
		relative_id = id;
		
		//generate star pixbuf
		starred = this.render_icon("starred", IconSize.MENU, null);
		not_starred = this.render_icon("not-starred", IconSize.MENU, null);
		
		cellHelper = new CellDataFunctionHelper(starred, not_starred);
		
		lm.songs_updated.connect(songs_updated);
		lm.songs_removed.connect(songs_removed);
		lm.song_played.connect(song_played);
		lm.playback_stopped.connect(playback_stopped);
		lm.current_cleared.connect(current_cleared);
		
		buildUI();
	}
	
	public void set_id(int id) {
		relative_id = id;
	}
	
	void updateSensitivities() {
		songRemove.set_sensitive(true);
		songRemove.set_label("Remove from Library");
		
		/*if(get_hint() == ViewWrapper.Hint.MUSIC) {
			songRemove.set_sensitive(true);
			songRemove.set_label("Remove from Library");
			columnNumber.set_active(false);
			columnNumber.set_visible(false);
		}
		else if(get_hint() == ViewWrapper.Hint.SIMILAR) {
			songRemove.set_sensitive(false);
		}
		else if(get_hint() == ViewWrapper.Hint.QUEUE) {
			songRemove.set_sensitive(true);
			songRemove.set_label("Remove from Queue");
			songMenuQueue.set_sensitive(false);
		}
		else if(get_hint() == ViewWrapper.Hint.HISTORY) {
			songRemove.set_sensitive(false);
		}
		else if(get_hint() == ViewWrapper.Hint.PLAYLIST) {
			songRemove.set_sensitive(true);
		}
		else if(get_hint() == ViewWrapper.Hint.SMART_PLAYLIST) {
			songRemove.set_sensitive(false);
		}
		else if(get_hint() == ViewWrapper.Hint.DEVICE) {
			songRemove.set_sensitive(false);
			songRemove.set_label("TODO: Remove from device");
		}
		else {
			songRemove.set_sensitive(false);
		}*/
	}
	
	public void buildUI() {
		view = new TreeView();
		
		cellTrack = new CellRendererText();
		cellTitle = new CellRendererText();
		cellLength = new CellRendererText();
		cellArtist = new CellRendererText();
		cellAlbum = new CellRendererText();
		cellGenre = new CellRendererText();
		cellYear = new CellRendererText();
		cellRating = new CellRendererPixbuf();
		cellSkips = new CellRendererText();
		cellPlays = new CellRendererText();
		cellBitrate = new CellRendererText();
		
		cellRating.xalign = 0.0f;
		
		//cellTitle.editable = false;
		//cellTitle.edited.connect(cellTitleEdited);
		
		/* id is always first and is stored as an int. Then the rest are (1)
		 * strings (for simplicity), and include:
		 * #, track, title, artist, album, genre, comment, year, rating, (9)
		 * bitrate, play count, last played, date added, file name, (5)
		 * bpm, length, file size, (3) */
		LinkedList<TreeViewColumn> to_use = new LinkedList<TreeViewColumn>();
		LinkedList<TreeViewColumn> originalOrder = new LinkedList<TreeViewColumn>();
		LinkedList<string> correctStringOrder = new LinkedList<string>();
		
		/*if(get_hint() == ViewWrapper.Hint.MUSIC)
			to_use = lm.music_setup.get_columns();
		else if(get_hint() == ViewWrapper.Hint.SIMILAR)
			to_use = lm.similar_setup.get_columns();
		else if(get_hint() == ViewWrapper.Hint.QUEUE)
			to_use = lm.queue_setup.get_columns();
		else if(get_hint() == ViewWrapper.Hint.HISTORY)
			to_use = lm.history_setup.get_columns();
		else if(get_hint() == ViewWrapper.Hint.PLAYLIST)
			to_use = lm.playlist_from_id(relative_id).tvs.get_columns();
		else if(get_hint() == ViewWrapper.Hint.SMART_PLAYLIST)
			to_use = lm.smart_playlist_from_id(relative_id).tvs.get_columns();*/
		if(get_hint() == ViewWrapper.Hint.PODCAST) {
			stdout.printf("plv line 397\n");
			to_use = lm.podcast_setup.get_columns();
		}
		else if(get_hint() == ViewWrapper.Hint.DEVICE_PODCAST) {
			to_use = new TreeViewSetup("Artist", Gtk.SortType.ASCENDING, ViewWrapper.Hint.DEVICE_PODCAST).get_columns();
		}
		
		stdout.printf("to_use is %d\n", to_use.size);
		
		/* put them in the order for treemodel */
		foreach(var tvc in to_use) {
			originalOrder.add(tvc);
			correctStringOrder.add(tvc.title);
		}
		
		int index = 0;
		foreach(TreeViewColumn tvc in originalOrder) {
			if(!(tvc.title == " " || tvc.title == "id")) {
				if(tvc.title == "Length")
					view.insert_column_with_data_func(-1, tvc.title, cellLength, cellHelper.lengthTreeViewFiller);
				else if(tvc.title == "Rating")
					view.insert_column_with_data_func(-1, tvc.title, cellRating, cellHelper.ratingTreeViewFiller);
				else if(tvc.title == "Date")
					view.insert_column_with_data_func(-1, tvc.title, cellYear, cellHelper.dateTreeViewFiller);
				else if(tvc.title == "Episode")
					view.insert_column_with_data_func(-1, tvc.title, cellTrack, cellHelper.intelligentTreeViewFiller);
				else if(tvc.title == "Name")
					view.insert_column_with_data_func(-1, tvc.title, cellTitle, cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Artist")
					view.insert_column_with_data_func(-1, tvc.title, cellArtist, cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Comments")
					view.insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Category")
					view.insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else
					view.insert_column(tvc, index);
				
				
				view.get_column(index).resizable = true;
				view.get_column(index).reorderable = false;
				view.get_column(index).clickable = true;
				view.get_column(index).sort_column_id = index;
				view.get_column(index).set_sort_indicator(false);
				view.get_column(index).visible = tvc.visible;
				view.get_column(index).sizing = Gtk.TreeViewColumnSizing.FIXED;
				view.get_column(index).fixed_width = tvc.fixed_width;
			}
			else if(tvc.title == " ") {
				view.insert_column(tvc, index);
				
				tvc.fixed_width = 24;
				tvc.clickable = false;
				tvc.sort_column_id = -1;
				tvc.resizable = false;
				tvc.reorderable = false;
				
				tvc.set_cell_data_func(tvc.get_cells().nth_data(0), iconDataFunc);
				tvc.set_cell_data_func(tvc.get_cells().nth_data(1), iconDataFunc);
			}
			else if(tvc.title == "id") {
				view.insert_column(tvc, index);
			}
			else {
				view.insert_column(tvc, index);
			}
			
			// add this widget crap so we can get right clicks
			view.get_column(index).widget = new Gtk.Label(tvc.title);
			view.get_column(index).widget.show();
			view.get_column(index).set_sort_indicator(false);
			Gtk.Widget ancestor = view.get_column(index).widget.get_ancestor(typeof(Gtk.Button));
			GLib.assert(ancestor != null);
			
			ancestor.button_press_event.connect(viewHeaderClick);
			view.get_column(index).notify["width"].connect(viewHeadersResized);
			
			++index;
		}
		
		//rearrangeColumns(correctStringOrder);
		viewColumnsChanged();
		
		podcast_model = new PodcastTreeModel(lm, get_column_strings(), render_icon("audio-volume-high", IconSize.MENU, null));
		
		podcast_model.set_sort_column_id(_columns.index_of(sort_column), sort_direction);
		
		view.set_model(podcast_model);
		view.set_headers_clickable(true);
		view.set_fixed_height_mode(true);
		view.rules_hint = true;
		view.set_reorderable(false);
		
		view.row_activated.connect(viewDoubleClick);
		view.button_press_event.connect(viewClick);
		
		//view.cursor_changed.connect_after(() => { update_rating_menu(); });
		view.button_release_event.connect(viewClickRelease);
		view.columns_changed.connect(viewColumnsChanged);
		view.key_press_event.connect(keyPressed);
		
		// allow selecting multiple rows
		view.get_selection().set_mode(SelectionMode.MULTIPLE);
		
		// drag source
		drag_source_set(view, Gdk.ModifierType.BUTTON1_MASK, {}, Gdk.DragAction.MOVE);
		Gtk.drag_source_add_uri_targets(view);
		
		// column chooser menu
		columnChooserMenu = new Menu();
		columnEpisode = new CheckMenuItem.with_label("Episode");
		columnName = new CheckMenuItem.with_label("Name");
		columnLength = new CheckMenuItem.with_label("Length");
		columnArtist = new CheckMenuItem.with_label("Artist");
		columnDate = new CheckMenuItem.with_label("Date");
		columnRating = new CheckMenuItem.with_label("Rating");
		columnComments = new CheckMenuItem.with_label("Comments");
		columnCategory = new CheckMenuItem.with_label("Category");
		updateColumnVisibilities();
		columnChooserMenu.append(columnEpisode);
		columnChooserMenu.append(columnName);
		columnChooserMenu.append(columnLength);
		columnChooserMenu.append(columnArtist);
		columnChooserMenu.append(columnDate);
		columnChooserMenu.append(columnCategory);
		columnChooserMenu.append(columnComments);
		columnChooserMenu.append(columnRating);
		columnEpisode.toggled.connect(columnMenuToggled);
		columnName.toggled.connect(columnMenuToggled);
		columnLength.toggled.connect(columnMenuToggled);
		columnArtist.toggled.connect(columnMenuToggled);
		columnDate.toggled.connect(columnMenuToggled);
		columnComments.toggled.connect(columnMenuToggled);
		columnCategory.toggled.connect(columnMenuToggled);
		columnRating.toggled.connect(columnMenuToggled);
		columnChooserMenu.show_all();
		
		
		//song list right click menu
		songMenuActionMenu = new Menu();
		songEditSong = new MenuItem.with_label("Edit Song Info");
		songFileBrowse = new MenuItem.with_label("Show in File Browser");
		songMenuQueue = new MenuItem.with_label("Queue");
		songMenuNewPlaylist = new MenuItem.with_label("New Playlist");
		songMenuAddToPlaylist = new MenuItem.with_label("Add to Playlist");
		songRemove = new MenuItem.with_label("Remove song");
		//songRateSongMenu = new Menu();
		//songRateSong = new MenuItem.with_label("Rate Song");
		rating_item = new RatingWidgetMenu();
		songMenuActionMenu.append(songEditSong);
		songMenuActionMenu.append(songFileBrowse);
		
		songMenuActionMenu.append(rating_item);
		
		songMenuActionMenu.append(new SeparatorMenuItem());
		songMenuActionMenu.append(songMenuQueue);
		songMenuActionMenu.append(songMenuNewPlaylist);
		songMenuActionMenu.append(songMenuAddToPlaylist);
		songMenuActionMenu.append(new SeparatorMenuItem());
		songMenuActionMenu.append(songRemove);
		songEditSong.activate.connect(songMenuEditClicked);
		songFileBrowse.activate.connect(songFileBrowseClicked);
		songMenuQueue.activate.connect(songMenuQueueClicked);
		songMenuNewPlaylist.activate.connect(songMenuNewPlaylistClicked);
		songRemove.activate.connect(songRemoveClicked);
		rating_item.activate.connect(songRateSong0Clicked);
		//songMenuActionMenu.show_all();
		
		updateSensitivities();
		
		this.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		
		this.add(view);
		
		this.podcast_model.rows_reordered.connect(modelRowsReordered);
		this.podcast_model.sort_column_changed.connect(sortColumnChanged);
		this.view.drag_begin.connect(onDragBegin);
        this.view.drag_data_get.connect(onDragDataGet);
        this.view.drag_end.connect(onDragEnd);
		this.vadjustment.value_changed.connect(viewScroll);
	}
	
	public void iconDataFunc(CellLayout layout, CellRenderer renderer, TreeModel model, TreeIter iter) {
		Value? id;
		model.get_value(iter, 0, out id);
		
		bool showIndicator = lm.song_from_id(id.get_int()).showIndicator;
		
		if(renderer is CellRendererPixbuf) {
			renderer.visible = !showIndicator;
			renderer.width = showIndicator ? 0 : 16;
		}
		if(renderer is CellRendererSpinner) {
			if(showIndicator) {
				((CellRendererSpinner)renderer).active = true;
			}
			renderer.visible = showIndicator;
			renderer.width = showIndicator ? 16 : 0;
		}
	}
	
	public void rearrangeColumns(LinkedList<string> correctOrder) {
		view.move_column_after(view.get_column(6), view.get_column(7));
		//stdout.printf("correctOrder.length = %d, view.get_columns.length() = %d\n", correctOrder.size, (int)view.get_columns().length());
		/* iterate through view.get_columns and if a column is not in the
		 * same location as correctOrder, move it there.
		*/
		for(int index = 0; index < view.get_columns().length(); ++index) {
			//stdout.printf("on index %d column %s originally moving to %d\n", index, view.get_column(index).title, correctOrder.index_of(view.get_column(index).title));
			if(view.get_column(index).title != correctOrder.get(index)) {
				view.move_column_after(view.get_column(index), view.get_column(correctOrder.index_of(view.get_column(index).title)));
			}
		}
	}
	
	public void cellTitleEdited(string path, string new_text) {
		/*int rowid;
		stdout.printf("done!\n");
		if((rowid = podcast_model.getRowidFromPath(path)) != 0) {
			lm.song_from_id(rowid).title = new_text;
			
			lm.update_song(lm.song_from_id(rowid), true);
		}
		cellTitle.editable = false; */
	}
	
	public virtual void sortColumnChanged() {
		updateTreeViewSetup();
	}
	
	public virtual void modelRowsReordered(TreePath path, TreeIter? iter, void* new_order) {
		/*if(ViewWrapper.Hint == "queue") {
			lm.clear_queue();
			
			TreeIter item;
			for(int i = 0; podcast_model.get_iter_from_string(out item, i.to_string()); ++i) {
				int id;
				podcast_model.get(item, 0, out id);
				
				lm.queue_song_by_id(id);
			}
		}*/
		
		if(get_is_current()) {
			set_as_current_list(0);
		}
		
		if(!scrolled_recently) {
			scrollToCurrent();
		}
	}
	
	public virtual void viewColumnsChanged() {
		if((int)(view.get_columns().length()) != lm.podcast_setup.PODCAST_COLUMN_COUNT) {
			stdout.printf("returning %d %d\n", (int)(view.get_columns().length()), lm.podcast_setup.PODCAST_COLUMN_COUNT);
			return;
		}
		stdout.printf("not returning\n");
		
		_columns.clear();
		foreach(TreeViewColumn tvc in view.get_columns()) {
			_columns.add(tvc.title);
		}
		
		updateTreeViewSetup();
	}
	
	public void updateColumnVisibilities() {
		int index = 0;
		foreach(TreeViewColumn tvc in view.get_columns()) {
			if(tvc.title == "Episode")
				columnEpisode.active = view.get_column(index).visible;
			else if(tvc.title == "Name")
				columnName.active = view.get_column(index).visible;
			else if(tvc.title == "Length")
				columnLength.active = view.get_column(index).visible;
			else if(tvc.title == "Artist")
				columnArtist.active = view.get_column(index).visible;
			else if(tvc.title == "Date")
				columnDate.active = view.get_column(index).visible;
			else if(tvc.title == "Rating")
				columnRating.active = view.get_column(index).visible;
			else if(tvc.title == "Comments")
				columnComments.active = view.get_column(index).visible;
			else if(tvc.title == "Category")
				columnCategory.active = view.get_column(index).visible;
			
			++index;
		}
	}
	
	public virtual void current_cleared() {
		set_is_current(false);
		
		if(lm.song_info.song != null)
			podcast_model.updateSong(lm.song_info.song.rowid, get_is_current());
	}
	
	
	public virtual void song_played(int id, int old) {
		if(old != -1) {
			podcast_model.updateSong(old, get_is_current());
			podcast_model.turnOffPixbuf(old);
		}
		
		if(!scrolled_recently) {
			scrollToCurrent();
		}
		
		podcast_model.updateSong(id, get_is_current());
		
		if(get_hint() == ViewWrapper.Hint.QUEUE) {
			_show_next = lm.queue();
			populate_view();
		}
	}
	
	void playback_stopped(int was_playing) {
		if(was_playing >= 1) {
			podcast_model.turnOffPixbuf(was_playing);
		}
	}
	
	public void update_songs(Collection<int> songs) {
		songs_updated(songs);
	}
	
	void songs_updated(Collection<int> ids) {
		podcast_model.updateSongs(ids, get_is_current());
		
		//since a song may have changed location, reset current
		if(get_is_current())
			set_as_current_list(0);
	}
	
	void songs_removed(LinkedList<int> ids) {
		removing_songs = true;
		podcast_model.removeSongs(ids);
		removing_songs = false;
	}
	
	void viewDoubleClick(TreePath path, TreeViewColumn column) {
		TreeIter item;
		
		// get db's rowid of row clicked
		podcast_model.get_iter(out item, path);
		Value id;
		podcast_model.get_value(item, 0, out id);
		
		set_as_current_list(id.get_int());
		
		// play the song
		lm.playSong(id.get_int());
		
		if(!lm.playing) {
			lw.playClicked();
		}
	}
	
	bool keyPressed(Gdk.EventKey event) {
		if(Regex.match_simple("[a-zA-Z0-9]", event.str)) {
			lw.searchField.grab_focus();
			lw.searchField.insert_at_cursor(event.str);
		}
		
		return false;
	}
	
	/* button_press_event */
	bool viewClick(Gdk.EventButton event) {
		if(event.type == Gdk.EventType.BUTTON_PRESS && event.button == 3) { //right click
			/* create add to playlist menu */
			Menu addToPlaylistMenu = new Menu();
			foreach(Playlist p in lm.playlists()) {
				MenuItem playlist = new MenuItem.with_label(p.name);
				addToPlaylistMenu.append(playlist);
				
				playlist.activate.connect( () => {
					TreeModel temp;
					foreach(TreePath path in view.get_selection().get_selected_rows(out temp)) {
						TreeIter item;
						temp.get_iter(out item, path);
						
						int id;
						temp.get(item, 0, out id);
						p.addSong(id);
					}
				});
			}
			
			addToPlaylistMenu.show_all();
			songMenuAddToPlaylist.submenu = addToPlaylistMenu;
			
			if(lm.playlists().size == 0)
				songMenuAddToPlaylist.set_sensitive(false);
			else
				songMenuAddToPlaylist.set_sensitive(true);
			
			songMenuActionMenu.show_all();
			
			int set_rating = -1;
			TreeModel temp;
			foreach(TreePath path in view.get_selection().get_selected_rows(out temp)) {
				TreeIter item;
				temp.get_iter(out item, path);
				
				int id;
				temp.get(item, 0, out id);
				
				if(set_rating == -1)
					set_rating = (int)lm.song_from_id(id).rating;
				else if(set_rating != lm.song_from_id(id).rating) {
					set_rating = 0;
					break;
				}
			}
			
			rating_item.rating_value = set_rating;
			songMenuActionMenu.popup (null, null, null, 3, get_current_event_time());
			
			TreeSelection selected = view.get_selection();
			selected.set_mode(SelectionMode.MULTIPLE);
			if(selected.count_selected_rows() > 1)
				return true;
			else
				return false;
		}
		else if(event.type == Gdk.EventType.BUTTON_PRESS && event.button == 1) {
			TreeIter iter;
			TreePath path;
			TreeViewColumn column;
			int cell_x;
			int cell_y;
			
			view.get_path_at_pos((int)event.x, (int)event.y, out path, out column, out cell_x, out cell_y);
			
			if(!podcast_model.get_iter(out iter, path))
				return false;
			
			/* don't unselect everything if multiple selected until button release
			 * for drag and drop reasons */
			if(view.get_selection().count_selected_rows() > 1) {
				if(view.get_selection().path_is_selected(path)) {
					if(((event.state & Gdk.ModifierType.SHIFT_MASK) == Gdk.ModifierType.SHIFT_MASK)|
						((event.state & Gdk.ModifierType.CONTROL_MASK) == Gdk.ModifierType.CONTROL_MASK)) {
							view.get_selection().unselect_path(path);
					}
					return true;
				}
				else if(!(((event.state & Gdk.ModifierType.SHIFT_MASK) == Gdk.ModifierType.SHIFT_MASK)|
				((event.state & Gdk.ModifierType.CONTROL_MASK) == Gdk.ModifierType.CONTROL_MASK))) {
					return true;
				}
				
				return false;
			}
		}
		
		return false;
	}
	
	/* button_release_event */
	private bool viewClickRelease(Gtk.Widget sender, Gdk.EventButton event) {
		/* if we were dragging, then set dragging to false */
		if(dragging && event.button == 1) {
			dragging = false;
			return true;
		}
		else if(((event.state & Gdk.ModifierType.SHIFT_MASK) == Gdk.ModifierType.SHIFT_MASK) | ((event.state & Gdk.ModifierType.CONTROL_MASK) == Gdk.ModifierType.CONTROL_MASK)) {
			return true;
		}
		else {
			TreePath path;
			TreeViewColumn tvc;
			int cell_x;
			int cell_y;
			int x = (int)event.x;
			int y = (int)event.y;
			
			if(!(view.get_path_at_pos(x, y, out path, out tvc, out cell_x, out cell_y))) return false;
			view.get_selection().unselect_all();
			view.get_selection().select_path(path);
			return false;
		}
	}
	
	private bool viewHeaderClick(Gtk.Widget w, Gdk.EventButton e) {
		if(e.button == 3) {
			columnChooserMenu.popup (null, null, null, 3, get_current_event_time());
			return true;
		}
		else if(e.button == 1) {
			updateTreeViewSetup();
			
			return false;
		}
		
		return false;
	}
	
	void viewHeadersResized() {
		updateTreeViewSetup();
	}
	
	void updateTreeViewSetup() {
		if(podcast_model == null || !(podcast_model is TreeSortable)) {
			return;
		}
		
		TreeViewSetup tvs;
			
		if(get_hint() == ViewWrapper.Hint.PODCAST)
			tvs = lm.podcast_setup;
		else // is PODCAST_DEVICE
			return;
			
		if(tvs == null)
			return;
		
		int sort_id = 5;
		SortType sort_dir = Gtk.SortType.ASCENDING;
		podcast_model.get_sort_column_id(out sort_id, out sort_dir);
		
		stdout.printf("sort id is %d and column length is %d\n", sort_id, _columns.size);
		
		if(sort_id <= 0)
			sort_id = 5;
		
		sort_column = _columns.get(sort_id);
		sort_direction = sort_dir;
		
		tvs.set_columns(get_columns());
		tvs.sort_column = _columns.get(sort_id);
		tvs.sort_direction = sort_dir;
		
		if(!playlistSaveTimeoutAdded) {
			playlistSaveTimeoutAdded = true;
			Timeout.add(2000, () => {
				lm.save_playlists(); 
				playlistSaveTimeoutAdded = false;
				
				return false; 
			});
		}
	}
	
	/** When the column chooser popup menu has a change/toggle **/
	public virtual void columnMenuToggled() {
		int index = 0;
		foreach(TreeViewColumn tvc in view.get_columns()) {
			if(tvc.title == "Episode")
				view.get_column(index).visible = columnEpisode.active;
			else if(tvc.title == "Name")
				view.get_column(index).visible = columnName.active;
			else if(tvc.title == "Length")
				view.get_column(index).visible = columnLength.active;
			else if(tvc.title == "Artist")
				view.get_column(index).visible = columnArtist.active;
			else if(tvc.title == "Date")
				view.get_column(index).visible = columnDate.active;
			else if(tvc.title == "Rating")
				view.get_column(index).visible = columnRating.active;
			else if(tvc.title == "Comments")
				view.get_column(index).visible = columnComments.active;
			else if(tvc.title == "Category")
				view.get_column(index).visible = columnCategory.active;
			
			++index;
		}
		
		if(get_hint() == ViewWrapper.Hint.PODCAST)
			lm.podcast_setup.set_columns(get_columns());
	}
	
	/** song menu popup clicks **/
	public virtual void songMenuEditClicked() {
		TreeSelection selected = view.get_selection();
		selected.set_mode(SelectionMode.MULTIPLE);
		TreeModel temp;
		
		//tempSongs.clear();
		var to_edit = new LinkedList<int>();
		foreach(TreePath path in selected.get_selected_rows(out temp)) {
			int id = podcast_model.getRowidFromPath(path.to_string());
			
			to_edit.add(id);
		}
		
		/*if(!GLib.File.new_for_path(song_from_id(id).file).query_exists() && song_from_id(id).file.contains(settings.getMusicFolder())) {
			song_from_id(id).unique_status_image = lw.render_icon("process-error-symbolic", Gtk.IconSize.MENU, null);
			lw.song_not_found(id);
		}
		else {*/
			SongEditor se = new SongEditor(lm, podcast_model.getOrderedSongs(), to_edit);
			se.songs_saved.connect(songEditorSaved);
		//}
	}
	
	public virtual void songEditorSaved(LinkedList<int> songs) {
		LinkedList<Song> toUpdate = new LinkedList<Song>();
		foreach(int i in songs)
			toUpdate.add(lm.song_from_id(i));
		
		lm.update_songs(toUpdate, true);
		
		if(get_hint() == ViewWrapper.Hint.SMART_PLAYLIST) {
			// make sure these songs still belongs here
		}
	}
	
	public virtual void songFileBrowseClicked() {
		TreeSelection selected = view.get_selection();
		selected.set_mode(SelectionMode.MULTIPLE);
		TreeModel temp;
		
		foreach(TreePath path in selected.get_selected_rows(out temp)) {
			TreeIter item;
			temp.get_iter(out item, path);
			
			int id;
			temp.get(item, 0, out id);
			Song s = lm.song_from_id(id);
			
			try {
				var file = File.new_for_path(s.file);
				Gtk.show_uri(null, file.get_parent().get_uri(), 0);
			}
			catch(GLib.Error err) {
				stdout.printf("Could not browse song %s: %s\n", s.file, err.message);
			}
			
			return;
		}
	}
	
	public virtual void songMenuQueueClicked() {
		TreeSelection selected = view.get_selection();
		selected.set_mode(SelectionMode.MULTIPLE);
		
		TreeModel model;
		
		foreach(TreePath path in selected.get_selected_rows(out model)) {
			TreeIter item;
			model.get_iter(out item, path);
			
			int id;
			model.get(item, 0, out id);
			
			lm.queue_song_by_id(id);
		}
	}
	
	public virtual void songMenuNewPlaylistClicked() {
		Playlist p = new Playlist();
		TreeSelection selected = view.get_selection();
		selected.set_mode(SelectionMode.MULTIPLE);
		
		TreeModel temp;
		foreach(TreePath path in selected.get_selected_rows(out temp)) {
			TreeIter item;
			podcast_model.get_iter(out item, path);
			
			Value id;
			podcast_model.get_value(item, 0, out id);
			
			p.addSong(id.get_int());
		}
		
		PlaylistNameWindow pnw = new PlaylistNameWindow(lw, p);
		pnw.playlist_saved.connect( (newP) => { 
			lm.add_playlist(p);
			lw.addSideListItem(p); 
		});
	}
	
	public virtual void songRemoveClicked() {
		TreeSelection selected = view.get_selection();
		selected.set_mode(SelectionMode.MULTIPLE);
		
		LinkedList<Song> toRemove = new LinkedList<Song>();
		LinkedList<int> toRemoveIDs = new LinkedList<int>();
		TreeModel temp;
		
		foreach(TreePath path in selected.get_selected_rows(out temp)) {
			TreeIter item;
			temp.get_iter(out item, path);
			
			int id;
			temp.get(item, 0, out id);
			Song s = lm.song_from_id(id);
			
			toRemoveIDs.add(id);
			
			if(get_hint() == ViewWrapper.Hint.PODCAST) {
				toRemove.add(s);
			}
		}
		
		if(get_hint() == ViewWrapper.Hint.PODCAST) {
			Gtk.MessageDialog md = new Gtk.MessageDialog(lm.lw, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, "Would you like to move the files to the trash?");
			md.title = "Move to Trash";
			
			if(md.run() == ResponseType.YES)
				lm.remove_songs(toRemove, true);
			else
				lm.remove_songs(toRemove, false);
			
			md.destroy();
		}
		
		podcast_model.removeSongs(toRemoveIDs);
		
		// in case all the songs from certain miller items were removed, update miller
		lw.miller.populateColumns("", podcast_model.getOrderedSongs());
	}
	
	public virtual void songRateSong0Clicked() {
		TreeSelection selected = view.get_selection();
		selected.set_mode(SelectionMode.MULTIPLE);
		TreeModel l_model;
		
		var los = new LinkedList<Song>();
		foreach(TreePath path in selected.get_selected_rows(out l_model)) {
			TreeIter item;
			l_model.get_iter(out item, path);
			
			int id;
			l_model.get(item, 0, out id);
			Song s = lm.song_from_id(id);
			
			s.rating = rating_item.rating_value;
			los.add(s);
		}
		
		lm.update_songs(los, false);
	}
	
	/*public void update_rating_menu() {
		TreeSelection selected = view.get_selection();
		selected.set_mode(SelectionMode.MULTIPLE);
		TreeModel l_model;

		foreach(TreePath path in selected.get_selected_rows(out l_model)) {
			TreeIter item;
			l_model.get_iter(out item, path);
			
			int id;
			l_model.get(item, 0, out id);
			Song s = lm.song_from_id(id);
			
			rating_item.rating_value = (int)s.rating;
		}
	}*/
	
	public void scrollToCurrent() {
		if(!get_is_current() || lm.song_info.song == null)
			return;
		
		TreeIter iter;
		for(int i = 0; podcast_model.get_iter_from_string(out iter, i.to_string()); ++i) {
			Value id;
			podcast_model.get_value(iter, 0, out id);

			if(view is TreeView && id.get_int() == lm.song_info.song.rowid) {
				view.scroll_to_cell(new TreePath.from_string(i.to_string()), null, false, 0.0f, 0.0f);
				scrolled_recently = false;
				
				return;
			}
		}
		
		scrolled_recently = false;
	}
	
	public virtual void viewScroll() {
		if(!scrolled_recently && get_is_current()) {
			Timeout.add(30000, () => {
				scrolled_recently = false;
				
				return false;
			});
			
			scrolled_recently = true;
		}
	}
	
	public virtual void onDragBegin(Gtk.Widget sender, Gdk.DragContext context) {
		dragging = true;
		lw.dragging_from_music = true;
		stdout.printf("drag begin\n");

		Gdk.drag_abort(context, Gtk.get_current_event_time());
		
		if(view.get_selection().count_selected_rows() == 1) {
			drag_source_set_icon_stock(this, Gtk.Stock.DND);
		}
		else if(view.get_selection().count_selected_rows() > 1) {
			drag_source_set_icon_stock(this, Gtk.Stock.DND_MULTIPLE);
		}
		else {
			return;
		}
	}
	
	public virtual void onDragDataGet(Gdk.DragContext context, Gtk.SelectionData selection_data, uint info, uint time_) {
        Gtk.TreeIter iter;
        Gtk.TreeModel temp_model;
        
        var rows = view.get_selection().get_selected_rows(out temp_model);
        string[] uris = null;
        
        foreach(TreePath path in rows) {
            temp_model.get_iter_from_string (out iter, path.to_string ());
            
			int id;
			temp_model.get (iter, 0, out id);
			stdout.printf("adding %s\n", lm.song_from_id(id).file);
			uris += ("file://" + lm.song_from_id(id).file);
		}
		
        if (uris != null)
            selection_data.set_uris(uris);
    }
    
    public virtual void onDragEnd(Gtk.Widget sender, Gdk.DragContext context) {
		dragging = false;
		lw.dragging_from_music = false;
		
		stdout.printf("drag end\n");
		
		//unset_rows_drag_dest();
		Gtk.drag_dest_set(this,
		                  Gtk.DestDefaults.ALL,
		                  {},
		                  Gdk.DragAction.COPY|
		                  Gdk.DragAction.MOVE
		                  );
	}
}
