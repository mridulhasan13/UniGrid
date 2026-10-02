/**
 * UniGrid Automated Onboarding & Verification Email Service
 * Production Web App for Google Apps Script.
 * Zero emojis used throughout the template.
 */

/**
 * HTTP POST Handler
 * Accepts JSON payload:
 * {
 *   "to": "student@example.com",
 *   "name": "Student Name",
 *   "department": "Industrial & Production Engineering",
 *   "batch": "51st Batch",
 *   "type": "pending" | "approved"   // or isApproved: true/false
 * }
 */
function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return responseJson({ status: "error", message: "Empty request payload." }, 400);
    }

    const data = JSON.parse(e.postData.contents);
    const to = (data.to || data.email || "").trim();

    if (!to) {
      return responseJson({ status: "error", message: "Missing recipient 'to' email address." }, 400);
    }

    const isApproved = data.type === "approved" || data.status === "approved" || data.isApproved === true;
    const name = (data.name || "Student").trim();
    const department = (data.department || "Academic Department").trim();
    const batch = (data.batch || "Active Session").trim();

    const refCode = Math.floor(1000 + Math.random() * 9000);
    const subject = isApproved 
      ? "UniGrid - Your Account Has Been Approved [#" + refCode + "]"
      : "UniGrid - Registration Received & Pending Approval [#" + refCode + "]";

    const htmlBody = generateUniGridTemplate({
      name: name,
      department: department,
      registeredEmail: to,
      batch: batch,
      isApproved: isApproved
    });

    MailApp.sendEmail({
      to: to,
      subject: subject,
      htmlBody: htmlBody,
      name: "UniGrid Academic Support"
    });

    return responseJson({
      status: "success",
      recipient: to,
      type: isApproved ? "approved" : "pending",
      remainingQuota: MailApp.getRemainingDailyQuota()
    });

  } catch (err) {
    return responseJson({
      status: "error",
      message: err.toString()
    }, 500);
  }
}

/**
 * HTTP GET Healthcheck Handler
 */
function doGet(e) {
  return responseJson({
    status: "online",
    service: "UniGrid Email Web App",
    remainingDailyQuota: MailApp.getRemainingDailyQuota()
  });
}

/**
 * JSON Response Helper
 */
function responseJson(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Universal Template Generator
 */
function generateUniGridTemplate(data) {
  const name = data.name;
  const department = data.department;
  const registeredEmail = data.registeredEmail;
  const batch = data.batch;
  const isApproved = data.isApproved;
  const uniqueToken = new Date().getTime();

  // Dynamic Content based on status
  const headline = isApproved ? "Your account has been approved" : "Registration under review";
  const subheadline = isApproved 
    ? "Welcome to the unified department portal. Your tools are now unlocked."
    : "Your profile was submitted successfully. Please wait while your Class Representative verifies your account.";
  
  const statusLabel = isApproved ? "Approved" : "Pending";
  const badgeStyle = isApproved 
    ? "background-color: #DCFCE7; color: #166534;" 
    : "background-color: #FEF3C7; color: #92400E;";

  // Official Brand Destinations
  const logoUrl = "https://unigrid.netlify.app/logo.png";
  const playStoreUrl = "https://play.google.com/store/apps/details?id=com.unigrid.app";
  const websiteUrl = "https://unigrid.netlify.app";
  const infoUrl = "https://info-unigrid.netlify.app";
  const supportEmail = "support.unigrid@gmail.com";

  // Official Social Media Channels
  const facebookUrl = "https://www.facebook.com/app.unigrid/";
  const instagramUrl = "https://www.instagram.com/unigrid.app/";
  const linkedinUrl = "https://www.linkedin.com/company/unigrid-app/";

  // Email-Safe CDN Hosted Icons
  const playIconUrl = "https://img.icons8.com/color/72/google-play.png";
  const webIconUrl = "https://img.icons8.com/ios/50/38bdf8/domain.png";
  const fbIconUrl = "https://img.icons8.com/ios/50/cbd5e1/facebook-new.png";
  const igIconUrl = "https://img.icons8.com/ios/50/cbd5e1/instagram-new.png";
  const liIconUrl = "https://img.icons8.com/ios/50/cbd5e1/linkedin.png";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>UniGrid Status</title>
  <style>
    body {
      margin: 0; padding: 0; background-color: #07111E;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      -webkit-font-smoothing: antialiased; color: #1E293B;
    }
    table { border-collapse: collapse; mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
    img { border: 0; outline: none; display: block; }
    a { text-decoration: none; }
    .wrapper { width: 100%; background-color: #07111E; padding: 30px 10px; }
    .email-container { max-width: 540px; margin: 0 auto; border-radius: 20px; overflow: hidden; box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6); }
    .perforations { background-color: #0B1626; padding: 12px 16px 4px 16px; text-align: center; }
    .dot { display: inline-block; width: 10px; height: 10px; background-color: #07111E; border-radius: 50%; margin: 0 5px; }
    .header-section { background-color: #0B1626; padding: 24px 30px 40px 30px; text-align: center; }
    .brand-title { color: #FFFFFF; font-size: 19px; font-weight: 800; letter-spacing: -0.3px; display: inline-block; vertical-align: middle; margin-left: 10px; }
    .hero-heading { color: #FFFFFF; font-size: 26px; font-weight: 800; line-height: 1.25; margin: 22px 0 10px 0; letter-spacing: -0.5px; }
    .hero-sub { color: #94A3B8; font-size: 13.5px; line-height: 1.5; max-width: 400px; margin: 0 auto; }
    .body-card { background-color: #FFFFFF; border-radius: 28px 28px 0 0; padding: 34px 26px 28px 26px; margin-top: -16px; }
    .salutation { font-size: 20px; font-weight: 700; color: #0F172A; margin-bottom: 20px; }
    .salutation em { font-style: italic; color: #0284C7; font-family: Georgia, serif; }
    .ticket-box { background-color: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 14px; padding: 16px 20px; margin-bottom: 24px; }
    .ticket-row { padding: 9px 0; border-bottom: 1px dashed #E2E8F0; }
    .ticket-row:last-child { border-bottom: none; }
    .ticket-label { color: #64748B; font-size: 13px; font-weight: 600; }
    .ticket-value { color: #0F172A; font-size: 13px; font-weight: 700; text-align: right; }
    .status-badge { font-size: 11px; font-weight: 700; padding: 3px 12px; border-radius: 20px; display: inline-block; text-transform: uppercase; letter-spacing: 0.5px; }
    .btn-cell-play { background-color: #0284C7; border-radius: 12px; padding: 12px 14px; box-shadow: 0 4px 14px rgba(2, 132, 199, 0.35); }
    .btn-cell-web { background-color: #0F172A; border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 12px; padding: 12px 14px; }
    .help-bar { margin-top: 20px; padding: 14px 18px; background-color: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 12px; text-align: center; font-size: 12.5px; color: #475569; }
    .help-bar a { color: #0284C7; font-weight: 700; }
    .footer-section { background-color: #0B1626; padding: 36px 30px; text-align: center; }
    .social-outline-btn { display: inline-block; width: 44px; height: 44px; border: 1px solid rgba(255, 255, 255, 0.18); border-radius: 50%; margin: 0 8px; vertical-align: middle; background-color: rgba(255, 255, 255, 0.04); }
    .legal-text { color: #64748B; font-size: 11.5px; line-height: 1.6; margin-top: 22px; }
    .legal-links a { color: #94A3B8; font-size: 11px; text-decoration: underline; margin: 0 6px; }
  </style>
</head>
<body>
  <div style="display:none;font-size:0px;color:transparent;line-height:0px;max-height:0px;overflow:hidden;mso-hide:all;">
    UniGrid Notification: ${statusLabel} status update. [ID: ${uniqueToken}]
  </div>

  <div class="wrapper">
    <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
      <tr>
        <td align="center">
          <div class="email-container">
            <div class="perforations">
              <span class="dot"></span><span class="dot"></span><span class="dot"></span><span class="dot"></span><span class="dot"></span>
              <span class="dot"></span><span class="dot"></span><span class="dot"></span><span class="dot"></span><span class="dot"></span>
              <span class="dot"></span><span class="dot"></span><span class="dot"></span><span class="dot"></span>
            </div>

            <div class="header-section">
              <table role="presentation" align="center" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <td style="vertical-align: middle;">
                    <img src="${logoUrl}" alt="UniGrid" width="34" height="34" style="border-radius: 8px;" />
                  </td>
                  <td style="vertical-align: middle;">
                    <span class="brand-title">UniGrid</span>
                  </td>
                </tr>
              </table>
              <h1 class="hero-heading">${headline}</h1>
              <p class="hero-sub">${subheadline}</p>
            </div>

            <div class="body-card">
              <div class="salutation">Hi <em>${name}</em>,</div>

              <div class="ticket-box">
                <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                  <tr class="ticket-row">
                    <td class="ticket-label" style="padding-bottom: 8px;">Department</td>
                    <td class="ticket-value" style="padding-bottom: 8px;">${department}</td>
                  </tr>
                  <tr class="ticket-row">
                    <td class="ticket-label" style="padding: 8px 0;">Registered Email</td>
                    <td class="ticket-value" style="padding: 8px 0;">${registeredEmail}</td>
                  </tr>
                  <tr class="ticket-row">
                    <td class="ticket-label" style="padding: 8px 0;">Batch</td>
                    <td class="ticket-value" style="padding: 8px 0;">${batch}</td>
                  </tr>
                  <tr class="ticket-row">
                    <td class="ticket-label" style="padding-top: 8px;">Status</td>
                    <td class="ticket-value" style="padding-top: 8px;">
                      <span class="status-badge" style="${badgeStyle}">${statusLabel}</span>
                    </td>
                  </tr>
                </table>
              </div>

              <!-- GOOGLE PLAY & WEB PORTAL BUTTONS IN A ROW -->
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <td width="48.5%" class="btn-cell-play" align="center">
                    <a href="${playStoreUrl}" target="_blank" style="display: block; width: 100%;">
                      <table role="presentation" border="0" cellspacing="0" cellpadding="0" align="center">
                        <tr>
                          <td style="vertical-align: middle; padding-right: 10px;">
                            <img src="${playIconUrl}" width="26" height="26" alt="Google Play" style="display: block;" />
                          </td>
                          <td style="vertical-align: middle; text-align: left;">
                            <div style="font-size: 9.5px; font-weight: 600; text-transform: uppercase; color: #E0F2FE; letter-spacing: 0.5px; line-height: 1;">GET IT ON</div>
                            <div style="font-size: 14.5px; font-weight: 800; color: #FFFFFF; line-height: 1.2;">Google Play</div>
                          </td>
                        </tr>
                      </table>
                    </a>
                  </td>
                  <td width="3%"></td>
                  <td width="48.5%" class="btn-cell-web" align="center">
                    <a href="${websiteUrl}" target="_blank" style="display: block; width: 100%;">
                      <table role="presentation" border="0" cellspacing="0" cellpadding="0" align="center">
                        <tr>
                          <td style="vertical-align: middle; padding-right: 10px;">
                            <img src="${webIconUrl}" width="22" height="22" alt="Web Portal" style="display: block;" />
                          </td>
                          <td style="vertical-align: middle; text-align: left;">
                            <div style="font-size: 9.5px; font-weight: 600; text-transform: uppercase; color: #94A3B8; letter-spacing: 0.5px; line-height: 1;">ACCESS ONLINE</div>
                            <div style="font-size: 14.5px; font-weight: 800; color: #FFFFFF; line-height: 1.2;">Web Portal</div>
                          </td>
                        </tr>
                      </table>
                    </a>
                  </td>
                </tr>
              </table>

              <div class="help-bar">
                Questions or assistance? Email <a href="mailto:${supportEmail}">${supportEmail}</a>
              </div>
            </div>

            <div class="footer-section">
              <table role="presentation" align="center" border="0" cellspacing="0" cellpadding="0" style="margin-bottom: 20px;">
                <tr>
                  <td style="vertical-align: middle;">
                    <img src="${logoUrl}" alt="UniGrid" width="28" height="28" style="border-radius: 7px; opacity: 0.9;" />
                  </td>
                  <td style="vertical-align: middle; padding-left: 8px;">
                    <span style="color: #FFFFFF; font-size: 15px; font-weight: 700; letter-spacing: -0.2px;">UniGrid</span>
                  </td>
                </tr>
              </table>

              <table role="presentation" align="center" border="0" cellspacing="0" cellpadding="0" style="margin: 10px auto 22px auto;">
                <tr>
                  <td style="padding: 0 6px;">
                    <a href="${facebookUrl}" class="social-outline-btn" target="_blank" title="Facebook">
                      <table role="presentation" width="44" height="44" border="0" cellspacing="0" cellpadding="0">
                        <tr><td align="center" valign="middle"><img src="${fbIconUrl}" width="20" height="20" alt="Facebook" style="display: block;" /></td></tr>
                      </table>
                    </a>
                  </td>
                  <td style="padding: 0 6px;">
                    <a href="${instagramUrl}" class="social-outline-btn" target="_blank" title="Instagram">
                      <table role="presentation" width="44" height="44" border="0" cellspacing="0" cellpadding="0">
                        <tr><td align="center" valign="middle"><img src="${igIconUrl}" width="20" height="20" alt="Instagram" style="display: block;" /></td></tr>
                      </table>
                    </a>
                  </td>
                  <td style="padding: 0 6px;">
                    <a href="${linkedinUrl}" class="social-outline-btn" target="_blank" title="LinkedIn">
                      <table role="presentation" width="44" height="44" border="0" cellspacing="0" cellpadding="0">
                        <tr><td align="center" valign="middle"><img src="${liIconUrl}" width="20" height="20" alt="LinkedIn" style="display: block;" /></td></tr>
                      </table>
                    </a>
                  </td>
                </tr>
              </table>

              <div class="legal-text">&copy; 2026 UniGrid Platform. All rights reserved.</div>
              <div class="legal-links" style="margin-top: 10px;">
                <a href="https://unigrid.netlify.app/privacy.html" target="_blank">Privacy Policy</a>
                <a href="${infoUrl}" target="_blank">About</a>
                <a href="https://unigrid.netlify.app/terms.html" target="_blank">Terms of Service</a>
              </div>
            </div>

          </div>
        </td>
      </tr>
    </table>
  </div>
</body>
</html>`;
}
