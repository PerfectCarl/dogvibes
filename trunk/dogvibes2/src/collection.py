import sys
import os
import tagpy
import sqlite3

from track import Track
from database import Database

class Collection:
    def add_track(self, track):
        db = Database()
        track_id = track.store()
        db.commit_statement('''select * from collection where track_id = ?''', [int(track_id)])
        if db.fetchone() == None:
            db.commit_statement('''insert into collection (track_id) values (?)''', [track_id])

    def create_track_from_uri(self, uri):
        db = Database()
        # TODO: better way than searching through ALL tracks?
        db.commit_statement('''select * from tracks where uri = ?''', [uri])
        row = db.fetchone()
        if row != None:
            return self.row_to_track(row)
        return None

    def row_to_track(self, row):
        #FIXME pleaz find out how this works
        track = Track(str(row[4]))
        track.title = str(row[1])
        track.artist = str(row[2])
        track.album = str(row[3])
        return track


    def index(self, path):
        for top, dirnames, filenames in os.walk(path):
            for filename in filenames:
                if filename.endswith('.mp3'):
                    full_path = os.path.join(top, filename);
                    f = tagpy.FileRef(full_path)
                    t = Track("file://" + full_path)
                    t.title = f.tag().title
                    t.artist = f.tag().artist
                    t.album = f.tag().album
                    a = f.audioProperties()
                    t.duration = a.length * 1000 # to msec
                    self.add_track(t)

    def search(self, query):
        db = Database()
        ret = []
        query = "%" + query + "%"
        # TODO: do a join between tracks and collection here. Not search on uri
        db.commit_statement('''select * from tracks where (title LIKE ? or artist LIKE ? or album LIKE ?) and uri LIKE ?''', (query, query, query, 'file://%'))
        row = db.fetchone()
        while row != None:
            ret += [self.row_to_track(row).__dict__]
            row = db.fetchone()
        return ret


if __name__ == '__main__':

    collection = Collection()
    collection.index('/home/brizz/music')
    print collection.search('hurricanes')
