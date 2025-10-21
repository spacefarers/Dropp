package com.michaelyang.dropp;

import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.widget.Button;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;

import com.michaelyang.dropp.databinding.ActivityMainBinding;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "MainActivity";
    private ActivityMainBinding binding;
    private SessionManager sessionManager;
    private OkHttpClient client;

    private final ActivityResultLauncher<Intent> filePickerLauncher = registerForActivityResult(
            new ActivityResultContracts.StartActivityForResult(),
            result -> {
                if (result.getResultCode() == RESULT_OK && result.getData() != null) {
                    Uri uri = result.getData().getData();
                    if (uri != null) {
                        uploadFile(uri);
                    }
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.d(TAG, "onCreate: Starting MainActivity");

        sessionManager = new SessionManager(this);
        client = HttpClient.getInstance();
        handleIntent(getIntent());

        boolean isLoggedIn = sessionManager.isLoggedIn();
        Log.d(TAG, "onCreate: User logged in: " + isLoggedIn);

        if (!isLoggedIn) {
            showLoginScreen();
        } else {
            showMainContent();
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        handleIntent(intent);
        recreate();
    }

    private void handleIntent(Intent intent) {
        if (intent == null) {
            return;
        }

        String action = intent.getAction();
        String type = intent.getType();

        if (Intent.ACTION_SEND.equals(action) && type != null) {
            Uri fileUri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (fileUri != null) {
                uploadFile(fileUri);
            }
        } else if (Intent.ACTION_SEND_MULTIPLE.equals(action) && type != null) {
            ArrayList<Uri> fileUris = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
            if (fileUris != null) {
                for (Uri uri : fileUris) {
                    uploadFile(uri);
                }
            }
        } else {
            // Original handling for deep links
            Uri data = intent.getData();
            if (data != null && "dropp".equals(data.getScheme()) && "auth".equals(data.getHost())) {
                String token = data.getQueryParameter("session_token");
                String userId = data.getQueryParameter("user_id");
                if (token != null && userId != null) {
                    sessionManager.saveSession(token, userId);
                }
            }
        }
    }

    private void showLoginScreen() {
        Log.d(TAG, "showLoginScreen: Displaying login screen");
        setContentView(R.layout.activity_login);
        Button loginButton = findViewById(R.id.login_button);
        loginButton.setOnClickListener(v -> {
            Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse("https://dropp.yangm.tech/login"));
            startActivity(browserIntent);
        });
    }

    private void showMainContent() {
        Log.d(TAG, "showMainContent: Displaying main content with fragments");
        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        setSupportActionBar(binding.toolbar);

        binding.fab.setOnClickListener(view -> {
            Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
            intent.setType("*/*");
            filePickerLauncher.launch(intent);
        });
        Log.d(TAG, "showMainContent: Main content layout set");
    }

    private void uploadFile(Uri fileUri) {
        try {
            InputStream inputStream = getContentResolver().openInputStream(fileUri);
            if (inputStream == null) {
                Toast.makeText(this, "Failed to open file.", Toast.LENGTH_SHORT).show();
                return;
            }
            byte[] fileBytes = getBytesFromInputStream(inputStream);
            long fileSize = fileBytes.length;
            String fileName = getFileName(fileUri);

            // Check storage capacity before uploading
            checkStorageAndUpload(fileBytes, fileName, fileSize, fileUri);
        } catch (IOException e) {
            Toast.makeText(this, "Failed to read file", Toast.LENGTH_SHORT).show();
        }
    }

    private void checkStorageAndUpload(byte[] fileBytes, String fileName, long fileSize, Uri fileUri) {
        Request request = new Request.Builder()
                .url("https://droppapi.yangm.tech/list")
                .addHeader("Authorization", "Bearer " + sessionManager.getToken())
                .build();

        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "Failed to check storage capacity", Toast.LENGTH_SHORT).show());
            }

            @Override
            public void onResponse(Call call, Response response) throws IOException {
                if (response.isSuccessful()) {
                    String responseBody = response.body().string();
                    try {
                        JSONObject jsonResponse = new JSONObject(responseBody);
                        JSONObject storage = jsonResponse.getJSONObject("storage");
                        long cap = storage.getLong("cap");
                        long used = storage.getLong("used");

                        // Check if upload would exceed capacity
                        if (used + fileSize > cap) {
                            runOnUiThread(() -> {
                                String message = String.format("Upload would exceed storage capacity. Available: %s, Required: %s",
                                        formatBytes(cap - used), formatBytes(fileSize));
                                Toast.makeText(MainActivity.this, message, Toast.LENGTH_LONG).show();
                            });
                            return;
                        }

                        // Proceed with upload
                        performUpload(fileBytes, fileName, fileUri);
                    } catch (JSONException e) {
                        runOnUiThread(() -> Toast.makeText(MainActivity.this, "Failed to parse storage info", Toast.LENGTH_SHORT).show());
                    }
                } else {
                    runOnUiThread(() -> Toast.makeText(MainActivity.this, "Failed to check storage capacity", Toast.LENGTH_SHORT).show());
                }
            }
        });
    }

    private void performUpload(byte[] fileBytes, String fileName, Uri fileUri) {
        String mediaTypeString = getContentResolver().getType(fileUri);
        MediaType mediaType = (mediaTypeString != null) ? MediaType.parse(mediaTypeString) : null;

        RequestBody fileBody = RequestBody.create(fileBytes, mediaType);

        RequestBody requestBody = new MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("file", fileName, fileBody)
                .build();

        Request request = new Request.Builder()
                .url("https://droppapi.yangm.tech/upload/")
                .addHeader("Authorization", "Bearer " + sessionManager.getToken())
                .post(requestBody)
                .build();

        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "Upload failed", Toast.LENGTH_SHORT).show());
            }

            @Override
            public void onResponse(Call call, Response response) {
                runOnUiThread(() -> {
                    if (response.isSuccessful()) {
                        Toast.makeText(MainActivity.this, "Upload successful", Toast.LENGTH_SHORT).show();
                        recreate();
                    } else {
                        Toast.makeText(MainActivity.this, "Upload failed: " + response.message(), Toast.LENGTH_SHORT).show();
                    }
                });
            }
        });
    }

    private String formatBytes(long bytes) {
        if (bytes < 1024) {
            return bytes + " B";
        } else if (bytes < 1024 * 1024) {
            return String.format("%.2f KB", (float) bytes / 1024);
        } else if (bytes < 1024 * 1024 * 1024) {
            return String.format("%.2f MB", (float) bytes / (1024 * 1024));
        } else {
            return String.format("%.2f GB", (float) bytes / (1024 * 1024 * 1024));
        }
    }

    private String getFileName(Uri uri) {
        String result = null;
        if (uri.getScheme().equals("content")) {
            try (Cursor cursor = getContentResolver().query(uri, null, null, null, null)) {
                if (cursor != null && cursor.moveToFirst()) {
                    int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                    if (index != -1) {
                        result = cursor.getString(index);
                    }
                }
            }
        }
        if (result == null) {
            result = uri.getPath();
            int cut = result.lastIndexOf('/');
            if (cut != -1) {
                result = result.substring(cut + 1);
            }
        }
        return result;
    }

    private byte[] getBytesFromInputStream(InputStream inputStream) throws IOException {
        ByteArrayOutputStream byteBuffer = new ByteArrayOutputStream();
        int bufferSize = 1024;
        byte[] buffer = new byte[bufferSize];
        int len;
        while ((len = inputStream.read(buffer)) != -1) {
            byteBuffer.write(buffer, 0, len);
        }
        return byteBuffer.toByteArray();
    }


    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.menu_main, menu);
        return true;
    }

    @Override
    public boolean onPrepareOptionsMenu(Menu menu) {
        MenuItem logoutItem = menu.findItem(R.id.action_logout);
        if (logoutItem != null) {
            logoutItem.setVisible(sessionManager.isLoggedIn());
        }
        return super.onPrepareOptionsMenu(menu);
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == R.id.action_logout) {
            sessionManager.clearSession();
            recreate();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    @Override
    public boolean onSupportNavigateUp() {
        return super.onSupportNavigateUp();
    }
}
