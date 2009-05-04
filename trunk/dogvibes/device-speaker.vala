using Gst;

public class DeviceSpeaker : GLib.Object, Speaker {
  private Bin bin;
  private Element devicesink;
  private Element queue2;
  private bool created;

  public string name { get; set; }

  construct {
    this.name = "alsabin";
    created = false;
  }

  public Bin get_speaker () {
    if (!created) {
      bin = new Bin(this.name);
      this.devicesink = ElementFactory.make ("alsasink", "alsasink");
      this.queue2 = ElementFactory.make ("queue2", "queue2");
      this.devicesink.set ("sync", false);
      stdout.printf ("Creating device sink\n");
      bin.add_many (this.queue2, this.devicesink);
      this.queue2.link (this.devicesink);
      GhostPad gpad = new GhostPad ("sink", this.queue2.get_static_pad("sink"));
      bin.add_pad (gpad);
      created = true;
    }
    return bin;
  }
}