package com.michaelyang.dropp;

public class File {
    private final String id;
    private final String name;
    private final long size;
    private final String blobUrl;

    public File(String id, String name, long size, String blobUrl) {
        this.id = id;
        this.name = name;
        this.size = size;
        this.blobUrl = blobUrl;
    }

    public String getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public long getSize() {
        return size;
    }

    public String getBlobUrl() {
        return blobUrl;
    }
}
