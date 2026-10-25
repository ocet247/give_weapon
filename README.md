# Weapon notes
* Shield charging will not work since `tf_wearable` is the only class that can be put in `m_hMyWearables` via VScript while charging requires it to be `tf_wearable_demoshield`.
* Consumables will not work on unordinary classes since game wouldn't be able to find a proper taunt to trigger.

# Custom slot notes
* Pressing a custom slot after it's already been selected can hide the viewmodel model due to the clientside prediction, this is only visual.
* A couple of bugs is present if quick weapon switching is disabled: `hud_fastswitch 0`.
