package com.agp.data;

public class OrderService {
    public int load(int id) {
        return id;
    }

    public int load(int id, String region) {
        return id + region.length();
    }

    public void save(Order order) {
    }
}
