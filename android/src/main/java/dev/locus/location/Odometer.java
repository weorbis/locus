package dev.locus.location;

import android.content.Context;
import android.content.SharedPreferences;
import android.location.Location;

import dev.locus.LocusPlugin;

public class Odometer {


    private static final String KEY_ODOMETER = "bg_odometer";

    private final SharedPreferences prefs;
    private double odometer = 0.0;
    private Location lastLocation;

    public Odometer(Context context) {
         this.prefs = context.getSharedPreferences(LocusPlugin.PREFS_NAME, Context.MODE_PRIVATE);
         this.odometer = readOdometer();
    }

    public double getDistance() {
        return odometer;
    }

    public synchronized void update(Location newLocation) {
        if (lastLocation == null) {
            lastLocation = newLocation;
            return;
        }
        float distance = newLocation.distanceTo(lastLocation);
        // Basic filter: ignore huge jumps > 100km or tiny < 1m if needed, 
        // but for now let's just acccumulate.
        odometer += distance;
        lastLocation = newLocation;
        writeOdometer(odometer);
    }
    
    public void setDistance(double distance) {
        this.odometer = distance;
        writeOdometer(distance);
        // Reset last location reference to avoid adding distance from a discontinuity
        lastLocation = null;
    }

    private double readOdometer() {
        return (double) prefs.getFloat(KEY_ODOMETER, 0.0f);
    }

    private void writeOdometer(double value) {
        prefs.edit().putFloat(KEY_ODOMETER, (float) value).apply();
    }
}
