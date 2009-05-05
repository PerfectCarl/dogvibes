using Gst;
using GConf;

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
    sources.append (new RadioSource ());

    /* initiate all speakers */
    speakers.append (new DeviceSpeaker ());
    speakers.append (new FakeSpeaker ());
    speakers.append (new ApexSpeaker ());
  }

  public static weak GLib.List<Source> get_sources () {
    return sources;
  }

  public static weak GLib.List<Speaker> get_speakers () {
    return speakers;
  }


  public string[] search (string query) {
    GLib.List<Track> tracks = new GLib.List<Track> ();

    foreach (Source source in sources) {
      foreach (Track track in source.search (query)) {
        //stdout.printf("%s - %s [%s]\n",
        //              track.artist, track.name, track.key);
        /* Tried to do this with concat but I ended up in an eternal loop... */
        tracks.append(track);
      }
    }

    int i = 0;
    string[] keys = new string[tracks.length ()];
    foreach (Track track in tracks) {
      keys[i] = track.key;
      i++;
    }

    return keys;
  }
}

[DBus (name = "com.Dogvibes.Amp")]
public class Amp : GLib.Object {
  /* the amp pipeline */
  private Pipeline pipeline = null;

  /* the amp pipline bus */
  private Bus bus = null;

  /* sources */
  private weak Source source;

  /* speakers */
  private weak Speaker speaker;

  /* elements */
  private Element src = null;
  private weak Element sink = null;
  private Element tee = null;
  private Element decodebin = null;
  private Element spotify = null;

  /* playqueue */
  GLib.List<Track> playqueue;
  uint playqueue_position;

  /* ugly hack waiting for mr fuck up */
  private bool spotify_in_use;

  weak GLib.List<Source> sources;
  weak GLib.List<Speaker> speakers;

  construct {
    sources = Dogvibes.get_sources ();
    speakers = Dogvibes.get_speakers ();

    source = sources.nth_data (0);
    spotify = source.get_src ();

    /* initiate the pipeline */
    pipeline = (Pipeline) new Pipeline ("dogvibes");

    /* create the amps decodebin */
    decodebin = ElementFactory.make ("decodebin2" , "decodebin2");
    decodebin.pad_added += pad_added;
    //pipeline.add (decodebin);

    /* create the tee */
    tee = ElementFactory.make ("tee", "tee");
    pipeline.add (tee);

    /* get pipline bus */
    bus = pipeline.get_bus ();
    bus.add_signal_watch ();
    bus.message += pipeline_eos;

    /* initiate play queue */
    playqueue = new GLib.List<Track> ();
    playqueue_position = 0;
  }

  private void pipeline_eos (Gst.Bus bus, Gst.Message mes) {
    if (mes.type == Gst.MessageType.EOS) {
      next_track ();
    }
  }

  private void pad_added (Element dec, Pad pad) {
    stdout.printf ("Found suitable plugins lets add the speaker\n");
    /* FIXME the speaker and the tee should not be added to the pipeline here */
    pad.link (tee.get_pad("sink"));
    tee.set_state (State.PAUSED);
  }

  /* Speaker API */
  public void connect_speaker (int nbr) {
    if (nbr > (speakers.length () - 1)) {
      stdout.printf ("Speaker %d does not exist\n", nbr);
      return;
    }

    speaker = speakers.nth_data (nbr);

    if (pipeline.get_by_name (speaker.name) == null) {
      State state;
      State pending;

      pipeline.get_state (out state, out pending, 0);
      pipeline.set_state (State.READY);
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

    if (pipeline.get_by_name (speaker.name) != null) {
      State state;
      State pending;
      pipeline.get_state (out state, out pending, 0);
      pipeline.set_state (State.READY);
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
    Track track;
    track = (Track) playqueue.nth_data (playqueue_position);

    if (src != null) {
      pipeline.remove (src);
      if (!spotify_in_use) {
        pipeline.remove (decodebin);
      }
    }

    if (track.key.substring(0,7) == "spotify") {
      src = spotify;
      source.set_key (track.key);
      pipeline.add (spotify);
      spotify.link (tee);
    } else {
      src = Element.make_from_uri (URIType.SRC, track.key , "source");
      pipeline.add_many (decodebin, src);
      src.link (decodebin);
    }
    pipeline.set_state (State.PLAYING);
  }

  public void queue (string key) {
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
    //source.set_key (track.key);
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
    //source.set_key (track.key);
    pipeline.set_state (state);
  }

  public void resume () {
    pipeline.set_state (State.PLAYING);
  }

  public void stop () {
    pipeline.set_state (State.NULL);
  }

  public void get_connected_speakers () {
	  stdout.printf("NOT IMPLEMENTED \n");
  }

  public void get_connected_source () {
	  stdout.printf("NOT IMPLEMENTED \n");
  }

  public void get_available_speakers () {
	  stdout.printf("NOT IMPLEMENTED \n");
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
