# Weapons notes
* Shield charging will not work since `tf_wearable` is the only class that can be put in `m_hMyWearables` via VScript while charging requires it to be `tf_wearable_demoshield`.
* Consumables will not work on unordinary classes since game wouldn't be able to find a proper taunt to trigger.

# Custom slots notes
* Using custom weapon slots might not work well on high ping since dummy weapons need to detect the moment player switches to them and VScript is serverside only, therefore nothing is smoothed out.
* A couple of bugs is present if quick weapon switching is disabled: `hud_fastswitch 0`.