"""Builds src/world/MenuRoom.rbxmx for the merged game.

The room (walls, windows, props, Duel Table, Deck Shelf, Trophy Wall, Radio) comes from the
friend's place; the Pack Party corner (with the 3D Pack Shelf) and the Shop Counter come from
Nash's place. Both places were made by the same room generator, so the stations line up.

    python3 tools/merge_room.py FRIEND.rbxlx NASH.rbxlx src/world/MenuRoom.rbxmx
(convert a binary .rbxl to .rbxlx first, for example with rbx-dom's rbx_binary / rbx_xml)
"""
import sys
import xml.etree.ElementTree as ET

FROM_NASH = ("PackParty", "ShopCounter")


def name_of(item):
    for p in item.find("Properties"):
        if p.get("name") == "Name":
            return p.text
    return None


def child(item, name):
    for k in item.findall("Item"):
        if name_of(k) == name:
            return k
    raise KeyError(name)


def menu_room(root):
    ws = [i for i in root.findall("Item") if i.get("class") == "Workspace"][0]
    return child(ws, "MenuRoom")


def main(friend_path, nash_path, out_path):
    friend = ET.parse(friend_path).getroot()
    nash = ET.parse(nash_path).getroot()
    room = menu_room(friend)
    stations = child(room, "Stations")
    nash_stations = child(menu_room(nash), "Stations")
    kids = list(stations)
    for key in FROM_NASH:
        old = child(stations, key)
        idx = kids.index(old)
        stations.remove(old)
        stations.insert(idx - (len(kids) - len(list(stations)) - 1), child(nash_stations, key))
    # Referents must be unique in one file: renumber everything.
    n = [0]

    def renumber(item):
        n[0] += 1
        item.set("referent", "RBX%08X" % n[0])
        for k in item.findall("Item"):
            renumber(k)

    renumber(room)
    out = ET.Element("roblox", {"version": "4"})
    out.append(room)
    ET.ElementTree(out).write(out_path, encoding="utf-8", xml_declaration=False)
    print("wrote", out_path, "stations:", [name_of(k) for k in stations.findall("Item")])


if __name__ == "__main__":
    main(*sys.argv[1:4])
