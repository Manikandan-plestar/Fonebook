# Implementation Plan - Unified Search & My Contacts UI Refinement

Enhance the Search feature to include local contacts and simplify the My Contacts management interface.

## Proposed Changes

### Fone Book Models
- No model changes required; we will map `MyContactItem` to `DirectoryContact` in-memory.

### Fone Book Screens

#### [MODIFY] [HomeScreen](file:///C:/Users/Plestar/StudioProjects/FoneBook/lib/screens/home_screen.dart)
- **Local Contact Search**:
    - Add `_localContacts` list to the state.
    - Fetch local contacts from the `get_my_contacts` API or local storage in `initState`.
    - In `_doSearch`, filter local contacts by name, title, or phone.
    - Combine results: Local matches first, then global database matches.
- **Result Differentiation**:
    - Pass a new `isMyContact` flag to `ContactCard`.
    - For local results, disable navigation to `DetailsScreen` and only allow calling.

#### [MODIFY] [ContactCard](file:///C:/Users/Plestar/StudioProjects/FoneBook/lib/widgets/contact_card.dart)
- **Visual Identifier**:
    - Add `bool isMyContact` property.
    - Display a "My Contact" pill/bubble below the name if `isMyContact` is true.

#### [MODIFY] [MyContactsScreen](file:///C:/Users/Plestar/StudioProjects/FoneBook/lib/screens/my_contacts_screen.dart)
- **List Interaction**:
    - Remove the row of icons (Call/Edit) from the contact list items.
    - Wrap the entire list item in an `InkWell` to trigger `_showEditDialog`.
- **Edit Dialog**:
    - Ensure the "Delete" button is clearly visible and positioned next to the action buttons in the dialog footer if not already there, as requested.

## Verification Plan

### Manual Verification
1. **Search Tab**:
    - Search for a contact that exists in "My Contacts".
    - Verify it appears at the top with a "My Contact" label.
    - Verify tapping the card does nothing (no details view).
    - Verify the green call button still works.
2. **My Contacts Tab**:
    - Verify the list items no longer show Call/Edit icons.
    - Tap a contact and verify the "Edit Contact" popup appears.
    - Confirm the "Delete" button is functional within the dialog.
