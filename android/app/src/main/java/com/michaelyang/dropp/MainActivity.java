package com.michaelyang.dropp;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;
import androidx.navigation.NavController;
import androidx.navigation.Navigation;
import androidx.navigation.ui.AppBarConfiguration;
import androidx.navigation.ui.NavigationUI;

import com.michaelyang.dropp.databinding.ActivityMainBinding;

public class MainActivity extends AppCompatActivity {

    private AppBarConfiguration appBarConfiguration;
    private ActivityMainBinding binding;
    private SessionManager sessionManager;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        sessionManager = new SessionManager(this);
        handleIntent(getIntent());

        if (!sessionManager.isLoggedIn()) {
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
        Uri data = intent.getData();
        if (data != null && "dropp".equals(data.getScheme()) && "auth".equals(data.getHost())) {
            String token = data.getQueryParameter("session_token");
            String userId = data.getQueryParameter("user_id");
            if (token != null && userId != null) {
                sessionManager.saveSession(token, userId);
            }
        }
    }

    private void showLoginScreen() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER);

        ImageView icon = new ImageView(this);
        icon.setImageResource(R.mipmap.ic_launcher);
        LinearLayout.LayoutParams iconParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
        );
        iconParams.setMargins(0, 0, 0, 32);
        icon.setLayoutParams(iconParams);

        TextView appName = new TextView(this);
        appName.setText(R.string.app_name);
        appName.setTextSize(32);

        Button loginButton = new Button(this);
        loginButton.setText("Login with Dropp");
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
        );
        buttonParams.setMargins(0, 32, 0, 0);
        loginButton.setLayoutParams(buttonParams);

        loginButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent browserIntent = new Intent(Intent.ACTION_VIEW, Uri.parse("https://dropp.yangm.tech/login"));
                startActivity(browserIntent);
            }
        });

        layout.addView(icon);
        layout.addView(appName);
        layout.addView(loginButton);

        setContentView(layout);
    }

    private void showMainContent() {
        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        setSupportActionBar(binding.toolbar);

        NavController navController = Navigation.findNavController(this, R.id.nav_host_fragment_content_main);
        appBarConfiguration = new AppBarConfiguration.Builder(navController.getGraph()).build();
        NavigationUI.setupActionBarWithNavController(this, navController, appBarConfiguration);
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
        if (sessionManager.isLoggedIn()) {
            NavController navController = Navigation.findNavController(this, R.id.nav_host_fragment_content_main);
            return NavigationUI.navigateUp(navController, appBarConfiguration)
                    || super.onSupportNavigateUp();
        }
        return super.onSupportNavigateUp();
    }
}
