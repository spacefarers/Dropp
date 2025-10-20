package com.michaelyang.dropp;

import android.content.Context;
import android.content.SharedPreferences;

public class SessionManager {
    private static final String PREF_NAME = "DroppSession";
    private static final String KEY_SESSION_TOKEN = "session_token";

    private SharedPreferences pref;
    private SharedPreferences.Editor editor;
    private Context _context;

    // Constructor
    public SessionManager(Context context) {
        this._context = context;
        pref = _context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        editor = pref.edit();
    }

    public void saveSessionToken(String token) {
        editor.putString(KEY_SESSION_TOKEN, token);
        editor.commit();
    }

    public String getSessionToken() {
        return pref.getString(KEY_SESSION_TOKEN, null);
    }

    public void clearSession() {
        editor.clear();
        editor.commit();
    }

    public boolean isLoggedIn() {
        return getSessionToken() != null;
    }
}
