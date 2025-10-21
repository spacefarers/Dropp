package com.michaelyang.dropp;

import okhttp3.OkHttpClient;
import okhttp3.logging.HttpLoggingInterceptor;

public class HttpClient {
    private static OkHttpClient instance;

    public static synchronized OkHttpClient getInstance() {
        if (instance == null) {
            HttpLoggingInterceptor logging = new HttpLoggingInterceptor();
            logging.setLevel(HttpLoggingInterceptor.Level.BASIC);
            instance = new OkHttpClient.Builder()
                    .addInterceptor(logging)
                    .build();
        }
        return instance;
    }
}
