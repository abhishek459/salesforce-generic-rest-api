# Generic SObject REST API Framework for Salesforce

A dynamic, reusable, and secure Apex REST framework for handling SObject integrations. This framework provides a single endpoint that can `upsert` any SObject and `insert` its related child records in a single, bulkified transaction, while allowing for custom logic injection without modifying the core code.

## The Challenge

A common challenge we encounter in our Salesforce development journey is the initial approach to integrations: building a dedicated Apex REST endpoint for each SObject. While this direct method works for a single requirement, it creates a significant maintenance challenge as an organization scales. This framework was built to solve that problem.

## Core Features

  * **Dynamic Endpoint:** A single endpoint handles any standard or custom SObject.
  * **Secure by Design:** Automatically enforces Field-Level Security (FLS) and object permissions for the running user.
  * **Scalable & Extensible:** Uses a Custom Metadata-driven factory pattern to allow developers to inject custom pre- and post-processing logic for any SObject without touching the core framework.
  * **Bulkified:** Designed to handle payloads with multiple records efficiently and respect governor limits.
  * **Parent-Child Support:** Upserts parent records and inserts their direct child records in the same transaction.
  * **Robust Error Handling:** Provides detailed, record-by-record success and error messages in the response payload.

## Architecture Overview

The framework is built with a clear separation of concerns to ensure maintainability and scalability:

  * **`SObjectResource`:** The main REST controller that handles the inbound HTTP request and orchestrates the process.
  * **`SObjectResourceHandler`:** A helper class that contains the core business logic for parsing, validating, and processing the data.
  * **`SObjectResourceModels`:** A container class for the API's data contracts (request and response DTOs).
  * **`IBeforeUpsertHandler` / `IAfterUpsertHandler`:** Apex interfaces that define the contract for custom logic injection.
  * **`BeforeUpsertHandlerFactory` / `AfterUpsertHandlerFactory`:** Factory classes that use Custom Metadata to dynamically instantiate the correct handler class for a given SObject.
  * **`SObject_Handler_Mapping__mdt`:** The Custom Metadata Type that maps SObjects to their corresponding handler classes.

-----

## Setup and Deployment

Follow these steps to set up the framework in your Salesforce org.

### 1\. Create the Custom Metadata Type

This step is critical and must be done **before** deploying any Apex code.

1.  Navigate to **Setup** -\> **Custom Code** -\> **Custom Metadata Types**.

2.  Click **New Custom Metadata Type**.

3.  Enter the following details:

      * **Label:** `SObject Handler Mapping`
      * **Plural Label:** `SObject Handler Mappings`
      * **Object Name:** `SObject_Handler_Mapping`
      * **Visibility:** `Public`

4.  Click **Save**.

5.  In the **Custom Fields** section, add the following three fields:

      * **Field 1: SObject API Name**

          * **Data Type:** `Text`
          * **Field Label:** `SObject API Name`
          * **Length:** `255`
          * **Field Name:** `SObject_API_Name`
          * **Required:** Check the box for "Always require a value in this field in order to save a record".

      * **Field 2: Handler Class Name**

          * **Data Type:** `Text`
          * **Field Label:** `Handler Class Name`
          * **Length:** `255`
          * **Field Name:** `Handler_Class_Name`
          * **Required:** Check the box for "Always require a value in this field in order to save a record".

      * **Field 3: Handler Type**

          * **Data Type:** `Picklist`
          * **Field Label:** `Handler Type`
          * **Values:** Enter the values `Before` and `After`, each on a separate line.
          * **Field Name:** `Handler_Type`
          * **Required:** Check the box for "Always require a value in this field in order to save a record".

### 2\. Deploy Apex Code

Now that the Custom Metadata Type exists, you can deploy the Apex classes in the following order.

**Deployment Wave 1: Models & Interfaces**

1.  `SObjectResourceModels.cls`
2.  `IBeforeUpsertHandler.cls`
3.  `IAfterUpsertHandler.cls`

**Deployment Wave 2: Logic & Handlers**

4.  `SObjectResourceHandler.cls`
5.  `BeforeUpsertHandlerFactory.cls`
6.  `AfterUpsertHandlerFactory.cls`
7.  `AccountBeforeUpsertHandler.cls` (Example Implementation)
8.  `AccountAfterUpsertHandler.cls` (Example Implementation)

**Deployment Wave 3: Endpoint Controller**

9.  `SObjectResource.cls`

### 3\. Configure API Access (Authentication)

For secure server-to-server integration, the recommended approach is to use an **External Client App** with the OAuth 2.0 Client Credentials Flow. This method allows your external application to authenticate directly without needing to impersonate a specific human user.

Here is a high-level overview of the setup process:

1.  **Create an Integration User:** Set up a dedicated, API-only user in Salesforce.
2.  **Create a Permission Set:** Create a permission set that grants all necessary permissions (Apex class access, object/field permissions).
3.  **Create and Configure an External Client App:** Set this up and enable it for the Client Credentials Flow.
4.  **Assign Permissions:** Assign your new permission set to the integration user and authorize it for the External Client App.

**For detailed, step-by-step instructions, please refer to the official Salesforce documentation:**

  * [External Client Apps Overview](https://help.salesforce.com/s/articleView?id=xcloud.external_client_apps.htm&type=5)
  * [Configure the Client Credentials Flow](https://help.salesforce.com/s/articleView?id=xcloud.configure_client_credentials_flow_for_external_client_apps.htm&type=5)

-----

## Usage Guide

Using the API is a two-step process. First, you obtain an access token using your External Client App credentials, and then you use that token to call the data gateway.

### Step 1: Obtain an Access Token

Your client application must first request an OAuth 2.0 access token from Salesforce.

  * **Method:** `POST`
  * **URL:** `{{instance_url}}/services/oauth2/token?grant_type=client_credentials&client_id={{client_id}}&client_secret={{client_secret}}`

**Note:** Replace `{{...}}` placeholders with your Salesforce My Domain URL and the credentials from your External Client App. A successful response will contain an `access_token`.

### Step 2: Call the Data Gateway to Upsert Records

Once you have the access token, include it as a bearer token in the `Authorization` header of your request.

  * **Method:** `POST`
  * **URL:** `{{instance_url}}/services/apexrest/v1/data-gateway/{SObjectApiName}`

**Note:** Replace `{SObjectApiName}` with the API name of the object you are targeting (e.g., `Account`).

#### **Headers**

  * `Authorization: Bearer <Your_Access_Token_From_Step_1>`
  * `Content-Type: application/json`

#### **Example Request Body**

This example upserts an `Account` and simultaneously inserts related `Contacts` and `Opportunities`.

```json
{
  "externalIdField": "External_Account_ID__c",
  "data": [
    {
      "Name": "Apex Global Corporation",
      "Industry": "Consulting",
      "BillingCity": "California",
      "External_Account_ID__c": "AGC-002",
      "Contacts": [
        {
          "FirstName": "Abhishek",
          "LastName": "Thulasi",
          "Email": "abhishek.thulasi@apexglobal.com",
          "Title": "Software Architect"
        },
        {
          "FirstName": "David",
          "LastName": "Chen",
          "Email": "david.chen@apexglobal.com",
          "Title": "Project Manager"
        }
      ],
      "Opportunities": [
        {
          "Name": "AGC - Q4 Enterprise License",
          "StageName": "Prospecting",
          "CloseDate": "2025-12-20",
          "Amount": 75000
        },
        {
          "Name": "AGC - 2026 Support Contract",
          "StageName": "Needs Analysis",
          "CloseDate": "2026-01-31",
          "Amount": 25000
        }
      ]
    }
  ]
}
```

-----

## Extending the Framework

To add custom logic for a new SObject (e.g., `Opportunity`), follow these steps:

1.  **Create a Handler Class:**
    Create a new Apex class that implements `IBeforeUpsertHandler` and/or `IAfterUpsertHandler`.

    ```apex
    // Example: OpportunityBeforeUpsertHandler.cls
    public class OpportunityBeforeUpsertHandler implements IBeforeUpsertHandler {
        public List<SObject> beforeUpsert(List<SObject> records) {
            for (SObject sObj : records) {
                Opportunity opp = (Opportunity) sObj;
                // Custom logic: Ensure StageName is not null
                if (opp.StageName == null) {
                    opp.StageName = 'Prospecting';
                }
            }
            return records;
        }
    }
    ```

2.  **Create a Custom Metadata Record:**

      * Go to **Setup** -\> **Custom Metadata Types** -\> **SObject Handler Mapping**.
      * Click **Manage Records**, then click **New**.
      * Enter the following details:
          * **Label:** `Opportunity Before Upsert`
          * **SObject API Name:** `Opportunity`
          * **Handler Class Name:** `OpportunityBeforeUpsertHandler`
          * **Handler Type:** `Before`
      * Click **Save**.

That's it\! The framework will now automatically execute your custom logic for any `Opportunity` records processed by the API.
