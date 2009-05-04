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
  private Source source;

  /* speakers */
  private Speaker speaker;
  //private Speaker fakespeaker = null;
  //private Speaker devicespeaker = null;

  /* elements */
  private Element src = null;
  private Element sink = null;
  //private Element sink1 = null;
  //private Element sink2 = null;
  private Element tee = null;

  /* playqueue */
  GLib.List<Track> playqueue;
  uint playqueue_position;

  weak GLib.List<Source> sources;
  weak GLib.List<Speaker> speakers;

  construct {
    /* FIXME all of this should be in a list */
    sources = Dogvibes.get_sources ();
    speakers = Dogvibes.get_speakers ();

    /* FIXME these should be removed */
    source = sources.nth_data (0);
    src = this.source.get_src ();

    tee = ElementFactory.make ("tee" , "tee");

    pipeline = (Pipeline) new Pipeline ("dogvibes");

    pipeline.add_many (src, tee);
    src.link (tee);

    /* play queue */
    playqueue = new GLib.List<Track> ();
    playqueue_position = 0;

    /* state is already NULL */
    pipeline.set_state (State.NULL);
  }

  /* Speaker API */
  public void connect_speaker (int nbr) {
    /* Fixme server crashes if you try to add already added speaker */
    if (nbr > (speakers.length () - 1)) {
      stdout.printf ("Speaker %d does not exist\n", nbr);
      return;
    }

    speaker = speakers.nth_data (nbr);

    /* fixme there are probably better ways to check if speaker is connected */
    if (pipeline.get_by_name (speaker.name) == null) {
      State state;
      State pending;

      pipeline.get_state (out state, out pending, 0);
      pipeline.set_state (State.NULL);
      sink = speaker.get_speaker ();
      pipeline.add (sink);
      tee.link (sink);
      pipeline.set_state (state);
    } else {
      stdout.printf ("Speaker already connected\n");
    }
  }

  public void disconnect_speaker (int nbr) {
    if (nbr > (speakers.length () - 1)) {
      stdout.printf ("Speaker %d does not exist\n", nbr);
      return;
    }

    speaker = speakers.nth_data (nbr);

    /* fixme there are probably better ways to check if speaker is connected */
    if (pipeline.get_by_name (speaker.name) != null) {
      State state;
      State pending;
      pipeline.get_state (out state, out pending, 0);
      pipeline.set_state (State.NULL);
      Element rm = pipeline.get_by_name (speaker.name);
      pipeline.remove (rm);
      tee.unlink (sink);
      pipeline.set_state (state);
    } else {
      stdout.printf ("Speaker not connected\n");
    }
  }

  /* Play Queue API */
  public void pause () {
    pipeline.set_state (State.PAUSED);
  }

  public void play () {
    /* FIXME do we need to set key here*/
    Track track;
    track = (Track) playqueue.nth_data (playqueue_position);
    source.set_key (track.key);
    pipeline.set_state (State.PLAYING);
  }

  public void queue (string key) {
    this.source.set_key (key);
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
    source.set_key (track.key);
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
    source.set_key (track.key);
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