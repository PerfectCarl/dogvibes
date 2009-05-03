using Gst;
using GConf;

public class Track : GLib.Object {
  public string key { get; set; }
  public string artist { get; set; }
}

[DBus (name = "com.Dogvibes.Dogvibes")]
public class Dogvibes : GLib.Object {
  /* list of all sources */
  public static GLib.List<Source> sources;

  /* list of all speakers */
  public static GLib.List<Speaker> speakers;

  construct {
    /* create lists of speakers and sources */
    sources = new GLib.List<Source> ();
    speakers = new GLib.List<Speaker> ();

    /* initiate all sources */
    sources.append (new SpotifySource ());
    sources.append (new FileSource ());

    /* initiate all speakers */
    speakers.append (new DeviceSpeaker ());
    speakers.append (new FakeSpeaker ());
  }

  public static weak GLib.List<Source> get_sources () {
    return sources;
  }

  public static weak GLib.List<Speaker> get_speakers () {
    return speakers;
  }


  public string[] search (string query) {
    /* this method is ugly as hell we need to understand how to concat string[] */
    var builder = new StringBuilder ();

    foreach (Source item in sources) {
      string[] res = item.search (query);
      foreach (string s in res) {
        stdout.printf ("%s\n", s);
        builder.append (s);
        builder.append ("$");
      }
    }

    return builder.str.split ("$");
  }
}

[DBus (name = "com.Dogvibes.Amp")]
public class Amp : GLib.Object {
  /* the amp pipeline */
  private Pipeline pipeline = null;

  /* sources */
  private Source spotify;

  /* speakers */
  private Speaker fakespeaker = null;
  private Speaker devicespeaker = null;

  /* elements */
  private Element src = null;
  private Element sink1 = null;
  private Element sink2 = null;
  private Element tee = null;

  /* playqueue */
  GLib.List<Track> playqueue;
  uint playqueue_position;

  construct {
    /* FIXME all of this should be in a list */
    weak GLib.List<Source> sources = Dogvibes.get_sources ();
    weak GLib.List<Source> speakers = Dogvibes.get_speakers ();

    /* FIXME these should be removed */
    spotify = new SpotifySource ();
    fakespeaker = new FakeSpeaker ();
    devicespeaker = new DeviceSpeaker ();

    src = this.spotify.get_src ();
    sink1 = this.devicespeaker.get_speaker ();
    sink2 = this.fakespeaker.get_speaker ();
    tee = ElementFactory.make ("tee" , "tee");

    pipeline = (Pipeline) new Pipeline ("dogvibes");
    /* uncomment if you want multiple speakers */
    //this.pipeline.add_many (src, tee, sink1, sink2);
    pipeline.add_many (src, tee, sink1);
    src.link (tee);
    tee.link (this.sink1);
    /* uncomment if you want multiple speakers */
    //this.tee.link (this.sink2);

    /* play queue */
    playqueue = new GLib.List<Track> ();
    playqueue_position = 0;

    /* State IS already NULL */
    pipeline.set_state (State.NULL);
  }

  /* Speaker API */
  public void connect_speaker (int speaker) {
    stdout.printf("NOT IMPLEMENTED %d\n", speaker);
  }

  public void disconnect_speaker (int speaker) {
    stdout.printf("NOT IMPLEMENTED %d\n", speaker);
  }

  /* Play Queue API */
  public void pause () {
    pipeline.set_state (State.PAUSED);
  }

  public void play () {
    /* FIXME do we need to set key here*/
    Track track;
    track = (Track) playqueue.nth_data (playqueue_position);
    spotify.set_key (track.key);
    pipeline.set_state (State.PLAYING);
  }

  public void queue (string key) {
    this.spotify.set_key (key);
    Track track = new Track ();
    track.key = key;
    track.artist = "Mim";
    playqueue.append (track);
  }

  public string[] get_all_tracks_in_queue () {
    var builder = new StringBuilder ();
    foreach (Track item in playqueue) {
      builder.append (item.key);
      builder.append (" ");
    }
    stdout.printf ("Play queue length %u\n", playqueue.length ());
    return builder.str.split (" ");
  }

  public void next_track () {
    State pending;
    State state;
    Track track;

    if (playqueue_position < (playqueue.length () - 1)) {
      playqueue_position = playqueue_position + 1;
    } else {
      stdout.printf ("Reached top of queue\n");
    }

    track = (Track) playqueue.nth_data (playqueue_position);
    pipeline.get_state (out state, out pending, 0);
    pipeline.set_state (State.NULL);
    spotify.set_key (track.key);
    pipeline.set_state (state);
  }

  public void previous_track () {
    State pending;
    State state;
    Track track;

    if (playqueue_position != 0) {
      playqueue_position = playqueue_position - 1;
    } else {
      stdout.printf ("Reached end of queue\n");
    }

    track = (Track) playqueue.nth_data (playqueue_position);
    pipeline.get_state (out state, out pending, 0);
    pipeline.set_state (State.NULL);
    spotify.set_key (track.key);
    pipeline.set_state (state);
  }

  public void resume () {
    pipeline.set_state (State.PLAYING);
  }

  public void stop () {
    pipeline.set_state (State.NULL);
  }
}

public void main (string[] args) {
  var loop = new MainLoop (null, false);
  Gst.init (ref args);

  try {
    /* register DBus session */
    var conn = DBus.Bus.get (DBus.BusType. SYSTEM);
    dynamic DBus.Object bus = conn.get_object ("org.freedesktop.DBus",
                                               "/org/freedesktop/DBus",
                                               "org.freedesktop.DBus");
    uint request_name_result = bus.request_name ("com.Dogvibes", (uint) 0);

    if (request_name_result == DBus.RequestNameReply.PRIMARY_OWNER) {
      /* register dogvibes server */
      var dogvibes = new Dogvibes ();
      conn.register_object ("/com/dogvibes/dogvibes", dogvibes);

      /* register amplifier */
      var amp = new Amp ();
      conn.register_object ("/com/dogvibes/amp/0", amp);
      loop.run ();
    }
  } catch (GLib.Error e) {
    stderr.printf ("Oops: %s\n", e.message);
  }
}

/* Maybe neede later on */
//	/* elements for final pipeline */
//	Element filter = null;
//	Element src = null;
//	Element sink = null;
//	/* inputs */
//	Element localmp3;
//	Element srse;
//	//Element lastfm;
//	/* outputs */
//	Element apexsink;
//	Element alsasink;
//	/* filter */
//	Element madfilter;
//
//	bool use_filter = false;
//	bool use_playbin = false;
//
//	stdout.printf ("PLAYING ");
//
//	/* FIXME, one pipeline isn't enough */
//	this.pipeline = (Pipeline) new Pipeline ("dogvibes");
//	this.pipeline.set_state (State.NULL);
//
//	/* inputs */
//	if (input == 0) {
//      src = this.spotify.get_src(key);
//	} else if (input == 1) {
//	  use_filter = true;
//	  stdout.printf("MP3 input ");
//	  localmp3 = ElementFactory.make ("filesrc", "file reader");
//	  madfilter = ElementFactory.make ("mad" , "mp3 decoder");
//	  localmp3.set("location", "../testmedia/beep.mp3");
//	  src = localmp3;
//	  filter = madfilter;
//	} else if (input == 2) {
//	  use_playbin = true;
//	  /* swedish webradio */
//	  stdout.printf("Internet radio ");
//	  srse = ElementFactory.make ("playbin", "Internet radio");
//	  srse.set ("uri", "mms://wm-live.sr.se/SR-P3-High");
//	  src = srse;
//	} else {
//	  stdout.printf("Error not correct input %d\n", input);
//	  return;
//	}
//
//	stdout.printf("on");
//
//	if (output == 0){
//	  stdout.printf(" ALSA sink \n");
//	  alsasink = ElementFactory.make ("alsasink", "alsasink");
//	  alsasink.set ("sync", false);
//	  sink = alsasink;
//	} else if (output == 1) {
//	  stdout.printf(" APEX sink \n");
//	  apexsink = ElementFactory.make ("apexsink", "apexsink");
//	  apexsink.set ("host", "192.168.1.3");
//	  apexsink.set ("volume", 100);
//	  apexsink.set ("sync", false);
//	  sink = apexsink;
//	} else {
//	  stdout.printf("Error not correct output %d\n", output);
//	  return;
//	}
//
//	/* ugly */
//	if (use_filter) {
//	  if (src != null && sink != null && filter != null) {
//		this.pipeline.add_many (src, filter, sink);
//		src.link (filter);
//		filter.link (sink);
//		this.pipeline.set_state (State.PLAYING);
//	  }
//	} else if (use_playbin) {
//	  if (src != null && sink != null) {
//		((Bin)this.pipeline).add (src);
//		this.pipeline.set_state (State.PLAYING);
//	  }
//	} else {
//	  if (src != null && sink != null) {
//		this.pipeline.add_many (src, sink);
//		src.link (sink);
//		this.pipeline.set_state (State.PLAYING);
//	  }
//	}