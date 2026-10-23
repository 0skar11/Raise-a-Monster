"""Check that the authored primary travel bar has three readable, equal controls."""
from pathlib import Path
import xml.etree.ElementTree as ET

asset = Path(__file__).resolve().parent.parent / "assets" / "TravelBar.rbxmx"
root = ET.parse(asset).getroot()
gui = root.find("Item")
assert gui is not None and gui.attrib["class"] == "ScreenGui"
assert gui.find("Properties/string[@name='Name']").text == "TravelBar"
buttons = root.findall(".//Item[@class='TextButton']")
assert len(buttons) == 3
assert not root.findall(".//Item[@class='ImageLabel']"), "Primary captions cannot depend on clipped bitmap text"
expected = [("HomeButton", "HOME", 0), ("TeleportShopButton", "SHOP", 144), ("TeleportArenaButton", "ARENA", 288)]
for button, (name, caption, x) in zip(buttons, expected):
    props = button.find("Properties")
    assert props.find("string[@name='Name']").text == name
    assert props.find("string[@name='Text']").text == caption
    assert props.find("UDim2[@name='Size']/XO").text == "136"
    assert props.find("UDim2[@name='Size']/YO").text == "44"
    assert props.find("UDim2[@name='Position']/XO").text == str(x)
    assert props.find("UDim2[@name='Position']/YO").text == "0"
    assert props.find("Font[@name='FontFace']/Family/url").text.endswith("GothamSSm.json")
    assert props.find("Font[@name='FontFace']/Weight").text == "700"
    assert props.find("bool[@name='TextWrapped']").text == "false"
    assert not button.findall("Item[@class='Frame']"), "No inner bevel may cover primary button text"
assert root.find(".//Item[@class='UIScale']/Properties/string[@name='Name']").text == "ResponsiveScale"
print("PASS: primary travel asset (3 equal, readable, responsive controls)")
