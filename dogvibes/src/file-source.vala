using Gst;

public class FileSource : GLib.Object, Source {
  private string dir;

  public FileSource (string dir) {
    stdout.printf("Creating file source\n");

    this.dir = dir;
    Collection c = new Collection();
    c.index(this.dir);
  }

  public weak GLib.List<Track> search (string query) {
    Collection collection = new Collection ();
    return collection.search (query);
  }

  public weak Track? create_track_from_uri (string uri) {
    return null;
  }
}